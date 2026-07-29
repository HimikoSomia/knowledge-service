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

  discard_on ActiveRecord::RecordNotFound
  discard_on Embedding::EmbeddingService::ConfigurationError
  discard_on Embedding::EmbeddingService::InvalidInputError
  retry_on  Embedding::EmbeddingService::RateLimitError, wait: :polynomially_longer, attempts: 10
  retry_on  Embedding::EmbeddingService::ServiceError,   wait: :polynomially_longer, attempts: 5
  retry_on  StandardError,                               wait: :polynomially_longer, attempts: 3

  def perform(document_id)
    document = Document.find(document_id)

    # Skip if already fully embedded with the current model.
    return if document.embedding_embedded?

    unless document.processed?
      Rails.logger.warn do
        "EmbedDocumentJob: document #{document_id} is not in 'processed' state " \
        "(#{document.status}) — skipping"
      end
      return
    end

    service = Embedding::OpenAiEmbeddingService.new

    unless service.configured?
      Rails.logger.warn "EmbedDocumentJob: OPENAI_API_KEY not configured — skipping document #{document_id}"
      document.update_columns(embedding_status: "not_configured")
      return
    end

    document.mark_embedding!

    chunks_to_embed = document.document_chunks
      .where(embedding: nil)
      .or(document.document_chunks.where.not(embedding_model: service.model))
      .order(:chunk_index)
      .to_a

    if chunks_to_embed.empty?
      Rails.logger.info "EmbedDocumentJob: document #{document_id} — all chunks already embedded"
      document.mark_embedded!
      return
    end

    Rails.logger.info do
      "EmbedDocumentJob: embedding #{chunks_to_embed.size} chunks for document #{document_id} " \
      "(model=#{service.model}, batch_size=#{service.batch_size})"
    end

    embed_batches(document, chunks_to_embed, service)

    # Verify nothing was left behind.
    remaining = document.document_chunks.where(embedding: nil).count
    if remaining > 0
      raise "EmbedDocumentJob: #{remaining} chunks still lack embeddings after processing " \
            "document #{document_id} — will retry"
    end

    document.mark_embedded!
    Rails.logger.info "EmbedDocumentJob: document #{document_id} fully embedded (#{document.chunk_count} chunks)"
  rescue => e
    friendly = log_and_friendly_message(e, context: "document #{document_id} embedding")
    document&.mark_embedding_failed!(friendly)
    raise
  end

  private

  def embed_batches(document, chunks, service)
    start_time = Time.current

    chunks.each_slice(service.batch_size).with_index(1) do |batch, batch_num|
      # Build the texts sent to OpenAI. Heading context is prepended to improve
      # semantic quality without altering the stored chunk.content.
      embed_texts = batch.map { |chunk| embed_text_for(chunk) }

      # ── API call is OUTSIDE any transaction ──────────────────────────────
      vectors = service.embed_texts(embed_texts)
      # ─────────────────────────────────────────────────────────────────────

      # Persist this batch inside a short transaction.
      now = Time.current
      DocumentChunk.transaction do
        batch.zip(vectors).each do |chunk, vector|
          chunk.update_columns(
            embedding:       vector,
            embedding_model: service.model,
            updated_at:      now
          )
        end
      end

      Rails.logger.info do
        "EmbedDocumentJob: batch #{batch_num} complete — " \
        "#{batch.size} chunks, document=#{document.id}"
      end
    end

    elapsed = (Time.current - start_time).round(2)
    Rails.logger.info "EmbedDocumentJob: document #{document.id} — all batches done in #{elapsed}s"
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
