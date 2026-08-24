class ProcessDocumentJob < ApplicationJob
  include DocumentProcessingLogging

  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(document_id, generation = nil)
    document = Document.find(document_id)
    job_id_for_failure = job_id

    claimed = document.claim_processing_stage!(
      generation: generation,
      job_id: job_id,
      execution: executions,
      queued_status: [ "pending", "processing" ],
      running_status: "processing"
    )
    return unless claimed

    document.file.blob.open do |tempfile|
      checksum = document.file.blob.checksum

      extractor = extractor_for(document.file.blob)
      result    = extractor.extract(tempfile)

      next_job = nil
      next_job_description = nil
      chunk_count = nil

      document.with_lock do
        document.reload
        unless document.processing_generation == generation.to_i && document.processing_job_id == job_id
          Rails.logger.info "ProcessDocumentJob: stale generation for document #{document_id}, skipping results"
          next
        end

        document.update_columns(extracted_content: result.to_h)
        chunk_count = Chunking::DocumentChunker.new(document, result).chunk!
        has_image_refs = result.sections.any? { |section| section["type"] == "image_ref" }

        attributes = {
          processed_at: Time.current,
          chunk_count: chunk_count,
          file_checksum: checksum,
          error_message: nil
        }

        if has_image_refs
          next_job = EnrichDocumentJob.new(document.id, generation)
          next_job_description = "enrichment queued"
          attributes.merge!(
            status: "enriching",
            enrichment_status: "pending",
            enriched_at: nil,
            processing_job_id: next_job.job_id,
            processing_job_execution: 0
          )
        elsif chunk_count.positive?
          next_job = EmbedDocumentJob.new(document.id, generation)
          next_job_description = "embedding queued"
          attributes.merge!(
            status: "embedding",
            enrichment_status: "not_required",
            processing_job_id: next_job.job_id,
            processing_job_execution: 0
          )
        else
          next_job_description = "processing complete"
          attributes.merge!(
            status: "processed",
            enrichment_status: "not_required",
            processing_job_id: nil,
            processing_job_execution: 0
          )
        end

        document.update_columns(attributes)
      end

      return unless chunk_count

      if next_job
        job_id_for_failure = next_job.job_id
        next_job.enqueue
      end

      Rails.logger.info do
        "ProcessDocumentJob: document #{document_id} extracted — #{chunk_count} chunks, #{next_job_description}"
      end
    end
  rescue ActiveRecord::RecordNotFound
    raise
  rescue => e
    friendly = log_and_friendly_message(e, context: "document #{document_id} extraction")
    document&.fail_current_processing!(generation: generation, job_id: job_id_for_failure || job_id, message: friendly)
    raise
  end

  private

  def extractor_for(blob)
    Extraction::DocumentExtractor.new.for(blob)
  end
end
