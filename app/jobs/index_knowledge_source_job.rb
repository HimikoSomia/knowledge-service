require "digest"

class IndexKnowledgeSourceJob < ApplicationJob
  queue_as :embedding

  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, _error|
    job.send(:finalize_failure, "unexpected_failure")
  end
  retry_on Embedding::OpenAiEmbeddingService::ServiceError,
           wait: :polynomially_longer,
           attempts: 5 do |job, _error|
    job.send(:finalize_failure, "provider_unavailable")
  end
  retry_on Embedding::OpenAiEmbeddingService::RateLimitError,
           wait: :polynomially_longer,
           attempts: 10 do |job, _error|
    job.send(:finalize_failure, "provider_unavailable")
  end
  discard_on Embedding::OpenAiEmbeddingService::ConfigurationError do |job, _error|
    job.send(:finalize_unindexed, "not_configured")
  end
  discard_on Embedding::OpenAiEmbeddingService::InvalidInputError do |job, _error|
    job.send(:finalize_failure, "invalid_content")
  end
  discard_on ActiveRecord::RecordNotFound

  def perform(knowledge_source_id, generation)
    source = KnowledgeSource.find(knowledge_source_id)
    return unless source.claim_indexing!(generation: generation, job_id: job_id, execution: executions)

    service = embedding_service
    unless service.configured?
      source.mark_unindexed!(generation: generation, job_id: job_id)
      return
    end

    parts = text_splitter.split(source.content)
    vectors = service.embed_texts(parts)
    chunks = parts.zip(vectors).each_with_index.map do |(content, embedding), index|
      {
        content: content,
        content_checksum: Digest::SHA256.hexdigest(content)[0, 16],
        token_count: (content.bytesize / 4.0).ceil,
        embedding: embedding,
        metadata: { "locator" => "Section #{index + 1}" }
      }
    end

    source.complete_indexing!(
      generation: generation,
      job_id: job_id,
      chunks: chunks,
      model: service.model
    )
  rescue => error
    Rails.logger.error "KnowledgeSource #{knowledge_source_id} indexing failed (#{error.class})"
    raise
  end

  private

  def embedding_service
    Embedding::OpenAiEmbeddingService.new
  end

  def text_splitter
    Chunking::TextSplitter.new
  end

  def finalize_failure(error_code)
    source = KnowledgeSource.find_by(id: arguments.first)
    source&.fail_indexing!(generation: arguments.second, job_id: job_id, error_code: error_code)
  end

  def finalize_unindexed(error_code)
    source = KnowledgeSource.find_by(id: arguments.first)
    source&.mark_unindexed!(generation: arguments.second, job_id: job_id, error_code: error_code)
  end
end
