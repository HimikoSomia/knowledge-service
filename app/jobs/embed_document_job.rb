# Embeds the document chunks produced by ProcessDocumentJob using the configured
# OpenAI embedding model and stores the resulting vectors in document_chunks.embedding.
#
# This job:
#   - Runs after ProcessDocumentJob, on the :embedding queue.
#   - Only embeds chunks that are missing an embedding or have a stale model.
#   - Processes chunks in configurable batches (no long-running DB transactions
#     around external API calls).
#   - Discards permanently on configuration errors; retries on transient failures.
#   - Marks the document as embedded only when every chunk has a vector.
#
class EmbedDocumentJob < ApplicationJob
  include DocumentProcessingLogging

  queue_as :embedding

  # Active Job searches handlers from bottom to top, so broad handlers must be
  # declared before the more specific retry and discard policies.
  retry_on  StandardError,                                      wait: :polynomially_longer, attempts: 3
  retry_on  Embedding::OpenAiEmbeddingService::ServiceError,   wait: :polynomially_longer, attempts: 5
  retry_on  Embedding::OpenAiEmbeddingService::RateLimitError, wait: :polynomially_longer, attempts: 10
  discard_on Embedding::OpenAiEmbeddingService::InvalidInputError
  discard_on Embedding::OpenAiEmbeddingService::ConfigurationError
  discard_on ActiveRecord::RecordNotFound

  def perform(document_id, generation = nil)
    document = Document.find(document_id)
    claimed = document.claim_processing_stage!(
      generation: generation,
      job_id: job_id,
      execution: executions,
      queued_status: [ "embedding", "ready" ],
      running_status: "embedding"
    )
    return unless claimed

    service = embedding_service

    unless document.processed_at?
      Rails.logger.warn do
        "EmbedDocumentJob: document #{document_id} has not been extracted — skipping"
      end
      return
    end

    unless document.document_chunks.exists?
      document.complete_current_processing!(
        generation: generation,
        job_id: job_id,
        attributes: { status: "processed" }
      )
      return
    end

    unless service.configured?
      Rails.logger.warn "EmbedDocumentJob: OPENAI_API_KEY not configured — skipping document #{document_id}"
      document.complete_current_processing!(
        generation: generation,
        job_id: job_id,
        attributes: { status: "processed" }
      )
      return
    end

    chunks_to_embed = chunks_needing_embedding(document, service).order(:chunk_index).to_a

    if chunks_to_embed.empty?
      Rails.logger.info "EmbedDocumentJob: document #{document_id} — all chunks already embedded"
      document.complete_current_processing!(
        generation: generation,
        job_id: job_id,
        attributes: { status: "ready", embedded_at: Time.current }
      )
      return
    end

    Rails.logger.info do
      "EmbedDocumentJob: embedding #{chunks_to_embed.size} chunks for document #{document_id} " \
      "(model=#{service.model}, batch_size=#{service.batch_size})"
    end

    return unless embed_batches(document, generation, chunks_to_embed, service)

    # Verify nothing was left behind.
    remaining = chunks_needing_embedding(document, service).count
    if remaining > 0
      raise "EmbedDocumentJob: #{remaining} chunks still lack embeddings after processing " \
            "document #{document_id} — will retry"
    end

    completed = document.complete_current_processing!(
      generation: generation,
      job_id: job_id,
      attributes: { status: "ready", embedded_at: Time.current }
    )
    return unless completed

    Rails.logger.info "EmbedDocumentJob: document #{document_id} fully embedded (#{document.chunk_count} chunks)"
  rescue => e
    friendly = log_and_friendly_message(e, context: "document #{document_id} embedding")
    document&.fail_current_processing!(generation: generation, job_id: job_id, message: friendly)
    raise
  end

  private

  def embedding_service
    Embedding::OpenAiEmbeddingService.new
  end

  def chunks_needing_embedding(document, service)
    chunks = document.document_chunks
    chunks
      .where(embedding: nil)
      .or(chunks.where(embedding_model: nil))
      .or(chunks.where.not(embedding_model: service.model))
  end

  def embed_batches(document, generation, chunks, service)
    start_time = Time.current

    chunks.each_slice(service.batch_size).with_index(1) do |batch, batch_num|
      return false unless document.processing_stage_current?(generation: generation, job_id: job_id)

      # Build the texts sent to OpenAI. Heading context is prepended to improve
      # semantic quality without altering the stored chunk.content.
      embed_texts = batch.map { |chunk| embed_text_for(chunk) }

      # ── API call is OUTSIDE any transaction ──────────────────────────────
      vectors = service.embed_texts(embed_texts)
      # ─────────────────────────────────────────────────────────────────────

      # Persist this batch inside a short transaction.
      now = Time.current
      persisted = document.with_lock do
        document.reload
        next false unless document.processing_generation == generation.to_i && document.processing_job_id == job_id

        batch.zip(vectors).each do |chunk, vector|
          chunk.update_columns(
            embedding:       vector,
            embedding_model: service.model,
            updated_at:      now
          )
        end
        true
      end
      return false unless persisted

      Rails.logger.info do
        "EmbedDocumentJob: batch #{batch_num} complete — " \
        "#{batch.size} chunks, document=#{document.id}"
      end
    end

    elapsed = (Time.current - start_time).round(2)
    Rails.logger.info "EmbedDocumentJob: document #{document.id} — all batches done in #{elapsed}s"
    true
  end

  # Returns the text that will be sent to OpenAI for this chunk.
  # Prepends the section heading when available to improve retrieval quality.
  # The original chunk.content is stored unchanged in the database.
  def embed_text_for(chunk)
    heading_content = chunk.metadata.dig("heading", "content").presence
    if heading_content
      "#{heading_content}\n\n#{chunk.content}"
    else
      chunk.content
    end
  end
end
