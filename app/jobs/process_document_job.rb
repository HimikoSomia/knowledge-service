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

      # Determine whether any image references need optional AI enrichment.
      has_image_refs = result.sections.any? { |s| s["type"] == "image_ref" }
      needs_embedding = chunk_count > 0

      document.mark_processed!(
        chunk_count,
        checksum,
        enrichment_status: has_image_refs ? "pending" : "not_applicable",
        embedding_status:  needs_embedding ? "pending"        : "not_applicable"
      )

      EnrichDocumentJob.perform_later(document.id) if has_image_refs
      EmbedDocumentJob.perform_later(document.id)  if needs_embedding

      Rails.logger.info do
        parts = [ "ProcessDocumentJob: document #{document_id} processed — #{chunk_count} chunks" ]
        parts << "enrichment queued" if has_image_refs
        parts << "embedding queued"  if needs_embedding
        parts.join(", ")
      end
    end
  rescue ActiveRecord::RecordNotFound
    raise
  rescue => e
    document&.mark_failed!(e.message)
    raise
  end
end
