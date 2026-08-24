# Asynchronous enrichment job that sends image_ref sections through a vision
# AI service to produce human-readable descriptions.
#
# This optional stage runs after extraction and always hands the document to the
# embedding stage when it finishes.
#
require "digest"

class EnrichDocumentJob < ApplicationJob
  include DocumentProcessingLogging

  queue_as :enrichment

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(document_id, generation = nil)
    document = Document.find(document_id)
    job_id_for_failure = job_id

    claimed = document.claim_processing_stage!(
      generation: generation,
      job_id: job_id,
      execution: executions,
      queued_status: "enriching",
      running_status: "enriching"
    )
    return unless claimed

    image_refs = pending_image_refs(document)

    if image_refs.empty?
      Rails.logger.info "EnrichDocumentJob: document #{document_id} has no image refs"
      job_id_for_failure = continue_to_embedding(document, generation)
      return
    end

    vision = vision_service

    unless vision.configured?
      Rails.logger.info "EnrichDocumentJob: vision service not configured, skipping document #{document_id}"
      job_id_for_failure = continue_to_embedding(document, generation)
      return
    end

    new_chunks = build_enriched_chunks(document, generation, image_refs, vision)
    return unless document.processing_stage_current?(generation: generation, job_id: job_id)

    return unless persist_enriched_chunks(document, generation, new_chunks)
    Rails.logger.info "EnrichDocumentJob: document #{document_id} enriched — #{new_chunks.size} new chunks"
    job_id_for_failure = continue_to_embedding(document, generation, enriched: true)
  rescue => e
    friendly = log_and_friendly_message(e, context: "document #{document_id} enrichment")
    document&.fail_current_processing!(
      generation: generation,
      job_id: @job_id_for_failure || job_id_for_failure || job_id,
      message: friendly
    )
    raise
  end

  private

  def vision_service
    Enrichment::OpenAiVisionService.new
  end

  def continue_to_embedding(document, generation, enriched: false)
    if document.document_chunks.exists?
      next_job = EmbedDocumentJob.new(document.id, generation)
      handed_off = document.handoff_processing!(
        generation: generation,
        job_id: job_id,
        next_job: next_job,
        status: "embedding",
        attributes: enriched ? { enriched_at: Time.current } : {}
      )
      return job_id unless handed_off

      @job_id_for_failure = next_job.job_id
      next_job.enqueue
      next_job.job_id
    else
      attributes = { status: "processed" }
      attributes[:enriched_at] = Time.current if enriched
      document.complete_current_processing!(generation: generation, job_id: job_id, attributes: attributes)
      job_id
    end
  end

  def pending_image_refs(document)
    document.extracted_content.fetch("sections", []).each_with_index.filter_map do |section, index|
      next unless section["type"] == "image_ref" && section["skipped_reason"] != "too_small"

      [ section, "image_ref:#{index}" ]
    end
  end

  def build_enriched_chunks(document, generation, image_refs, vision)
    chunks = []

    image_refs.each do |image_ref, source_key|
      break unless document.processing_stage_current?(generation: generation, job_id: job_id)

      description = begin
        vision.describe_image_from_document(document, image_ref)
      rescue => e
        Rails.logger.error "EnrichDocumentJob: vision failed for image_ref #{image_ref.inspect}: #{e.message}"
        nil
      end

      next if description.blank?

      chunks << {
        source_key:  source_key,
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

  def persist_enriched_chunks(document, generation, chunks)
    document.with_lock do
      document.reload
      return false unless document.processing_generation == generation.to_i && document.processing_job_id == job_id

      if chunks.any?
        existing_indexes = document.document_chunks.where(source_key: chunks.pluck(:source_key)).pluck(:source_key, :chunk_index).to_h
        maximum_index = document.document_chunks.maximum(:chunk_index)
        next_index = maximum_index ? maximum_index + 1 : 0
        now = Time.current
        records = chunks.map do |chunk|
          chunk_index = existing_indexes[chunk[:source_key]] || next_index.tap { next_index += 1 }
          {
            document_id: document.id,
            source_key: chunk[:source_key],
            chunk_index: chunk_index,
            content: chunk[:content],
            content_checksum: Digest::SHA256.hexdigest(chunk[:content])[0, 16],
            token_count: (chunk[:content].bytesize / 4.0).ceil,
            page_number: chunk[:page_number],
            metadata: chunk[:metadata],
            embedding: nil,
            embedding_model: nil,
            created_at: now,
            updated_at: now
          }
        end
        DocumentChunk.upsert_all(
          records,
          unique_by: "index_document_chunks_on_document_and_source_key",
          update_only: %i[content content_checksum token_count page_number metadata embedding embedding_model]
        )
      end

      document.update_columns(chunk_count: document.document_chunks.count)
      true
    end
  end
end
