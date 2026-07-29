# Asynchronous enrichment job that sends image_ref sections through a vision
# AI service to produce human-readable descriptions.
#
# This job runs AFTER ProcessDocumentJob and is entirely optional. Failure here
# does not affect the document's primary status — only enrichment_status changes.
#
# Current behavior:
#   - If no vision service is configured, the job logs and marks enrichment as
#     not_applicable, avoiding repeated retries.
#   - If the vision service raises NotImplementedError (stub not yet implemented),
#     the same applies.
#   - Other errors are retried (via retry_on) before marking enrichment failed.
#
class EnrichDocumentJob < ApplicationJob
  include DocumentProcessingLogging

  queue_as :enrichment

  discard_on ActiveRecord::RecordNotFound
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(document_id)
    document = Document.find(document_id)

    return if document.enrichment_enriched?

    image_refs = pending_image_refs(document)

    if image_refs.empty?
      Rails.logger.info "EnrichDocumentJob: document #{document_id} has no image refs, marking not_applicable"
      document.update_columns(enrichment_status: "not_applicable")
      return
    end

    vision = Enrichment::OpenAiVisionService.new

    unless vision.configured?
      Rails.logger.info "EnrichDocumentJob: vision service not configured, skipping document #{document_id}"
      document.update_columns(enrichment_status: "not_applicable")
      return
    end

    document.mark_enriching!
    new_chunks = build_enriched_chunks(document, image_refs, vision)

    if new_chunks.any?
      base_index = document.document_chunks.count
      now = Time.current
      records = new_chunks.each_with_index.map do |chunk, idx|
        {
          document_id: document.id,
          chunk_index:  base_index + idx,
          content:      chunk[:content],
          page_number:  chunk[:page_number],
          metadata:     chunk[:metadata],
          created_at:   now,
          updated_at:   now
        }
      end
      DocumentChunk.insert_all!(records)
      document.update_columns(chunk_count: document.document_chunks.count)
    end

    document.mark_enriched!
    Rails.logger.info "EnrichDocumentJob: document #{document_id} enriched — #{new_chunks.size} new chunks"

    # Re-queue embedding so the new enrichment chunks get their vectors.
    EmbedDocumentJob.perform_later(document.id) if new_chunks.any?
  rescue NotImplementedError => e
    Rails.logger.warn "EnrichDocumentJob: vision service not implemented for document #{document_id}: #{e.message}"
    document&.update_columns(enrichment_status: "not_applicable")
    # Do not re-raise — expected until the vision service is implemented.
  rescue => e
    friendly = log_and_friendly_message(e, context: "document #{document_id} enrichment")
    document&.mark_enrichment_failed!(friendly)
    raise
  end

  private

  def pending_image_refs(document)
    document.extracted_content
            .fetch("sections", [])
            .select { |s| s["type"] == "image_ref" && s["skipped_reason"] != "too_small" }
  end

  def build_enriched_chunks(document, image_refs, vision)
    chunks = []

    image_refs.each do |image_ref|
      description = begin
        vision.describe_image_from_document(document, image_ref)
      rescue => e
        Rails.logger.error "EnrichDocumentJob: vision failed for image_ref #{image_ref.inspect}: #{e.message}"
        nil
      end

      next if description.blank?

      chunks << {
        content:     description,
        page_number: image_ref["page_number"],
        metadata:    {
          "type"        => "image_description",
          "source_type" => "ai_vision",
          "image_index" => image_ref["image_index"],
          "heading"     => image_ref["heading"]
        }.compact
      }
    end

    chunks
  end
end
