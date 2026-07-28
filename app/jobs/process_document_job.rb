class ProcessDocumentJob < ApplicationJob
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

      extractor = Extraction::DocumentExtractor.new.for(document.file.blob)
      result    = extractor.extract(tempfile)

      document.update_columns(extracted_content: result.to_h)

      chunk_count = Chunking::DocumentChunker.new(document, result).chunk!
      document.mark_processed!(chunk_count, checksum)

      Rails.logger.info "ProcessDocumentJob: document #{document_id} processed — #{chunk_count} chunks created"
    end
  rescue ActiveRecord::RecordNotFound
    raise
  rescue => e
    document&.mark_failed!(e.message)
    raise
  end
end
