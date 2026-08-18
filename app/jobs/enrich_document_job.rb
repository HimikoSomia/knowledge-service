# Asynchronous enrichment job that sends image_ref sections through a vision
# AI service to produce human-readable descriptions.
#
# This optional stage runs after extraction and always hands the document to the
# embedding stage when it finishes.
#
class EnrichDocumentJob < ApplicationJob
  include DocumentProcessingLogging

  queue_as :enrichment

  discard_on ActiveRecord::RecordNotFound
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(document_id)
    document = Document.find(document_id)

    return if document.ready?

    image_refs = pending_image_refs(document)

    if image_refs.empty?
      Rails.logger.info "EnrichDocumentJob: document #{document_id} has no image refs"
      continue_to_embedding(document)
      return
    end

    vision = vision_service

    unless vision.configured?
      Rails.logger.info "EnrichDocumentJob: vision service not configured, skipping document #{document_id}"
      continue_to_embedding(document)
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
    continue_to_embedding(document)
  rescue => e
    friendly = log_and_friendly_message(e, context: "document #{document_id} enrichment")
    document&.mark_failed!(friendly)
    raise
  end

  private

  def vision_service
    Enrichment::OpenAiVisionService.new
  end

  def continue_to_embedding(document)
    if document.document_chunks.exists?
      document.mark_embedding!
      EmbedDocumentJob.perform_later(document.id)
    else
      document.mark_processed!
    end
  end

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
