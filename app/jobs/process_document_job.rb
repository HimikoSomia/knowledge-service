class ProcessDocumentJob < ApplicationJob
  include DocumentProcessingLogging

  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(document_id)
    document = Document.find(document_id)

    document.file.blob.open do |tempfile|
      checksum = document.file.blob.checksum

      if document.already_processed_for?(checksum)
        Rails.logger.info "ProcessDocumentJob: document #{document_id} already processed for checksum #{checksum}, skipping"
        next
      end

      document.mark_processing!

      extractor = extractor_for(document.file.blob)
      result    = extractor.extract(tempfile)

      document.update_columns(extracted_content: result.to_h)

      chunk_count = Chunking::DocumentChunker.new(document, result).chunk!

      has_image_refs = result.sections.any? { |s| s["type"] == "image_ref" }
      document.record_extraction!(chunk_count, checksum)

      next_job = if has_image_refs
        document.mark_enriching!
        EnrichDocumentJob.perform_later(document.id)
        "enrichment queued"
      elsif chunk_count.positive?
        document.mark_embedding!
        EmbedDocumentJob.perform_later(document.id)
        "embedding queued"
      else
        document.mark_processed!
        "processing complete"
      end

      Rails.logger.info do
        "ProcessDocumentJob: document #{document_id} extracted — #{chunk_count} chunks, #{next_job}"
      end
    end
  rescue ActiveRecord::RecordNotFound
    raise
  rescue => e
    friendly = log_and_friendly_message(e, context: "document #{document_id} extraction")
    document&.mark_failed!(friendly)
    raise
  end

  private

  def extractor_for(blob)
    Extraction::DocumentExtractor.new.for(blob)
  end
end
