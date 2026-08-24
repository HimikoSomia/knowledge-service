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

  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.send(:finalize_exhausted_enrichment, error)
  end
  retry_on Enrichment::OpenAiVisionService::TransientError,
           wait: :polynomially_longer,
           attempts: 3 do |job, error|
    job.send(:finalize_exhausted_enrichment, error)
  end
  discard_on Enrichment::OpenAiVisionService::ConfigurationError do |job, error|
    job.send(:finalize_exhausted_enrichment, error)
  end
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

    current = document.update_current_processing!(
      generation: generation,
      job_id: job_id,
      attributes: { enrichment_status: "in_progress", enriched_at: nil }
    )
    return unless current

    image_refs = eligible_image_refs(document)

    if image_refs.empty?
      Rails.logger.info "EnrichDocumentJob: document #{document_id} has no image refs"
      job_id_for_failure = continue_to_embedding(
        document,
        generation,
        enrichment_status: "not_required",
        completed_at: nil
      )
      return
    end

    pending_refs = image_refs.reject { |_, _, section| terminal_image_outcome?(section) }

    if pending_refs.empty?
      job_id_for_failure = finish_recorded_outcome(document, generation, image_refs)
      return
    end

    vision = vision_service

    unless vision.configured?
      Rails.logger.info "EnrichDocumentJob: vision service not configured, skipping document #{document_id}"
      skipped = pending_refs.map do |_, source_key, _|
        image_outcome(source_key, status: "skipped", error_code: "not_configured")
      end
      return unless persist_enrichment_results(document, generation, [], skipped)

      job_id_for_failure = finish_recorded_outcome(document, generation, image_refs)
      return
    end

    new_chunks, outcomes = build_enrichment_results(document, generation, pending_refs, vision)
    return unless document.processing_stage_current?(generation: generation, job_id: job_id)

    return unless persist_enrichment_results(document, generation, new_chunks, outcomes)
    Rails.logger.info "EnrichDocumentJob: document #{document_id} enriched — #{new_chunks.size} new chunks"
    job_id_for_failure = finish_recorded_outcome(document, generation, image_refs)
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

  def continue_to_embedding(document, generation, enrichment_status:, completed_at: Time.current)
    outcome_attributes = {
      enrichment_status: enrichment_status,
      enriched_at: completed_at
    }

    if document.document_chunks.exists?
      next_job = EmbedDocumentJob.new(document.id, generation)
      handed_off = document.handoff_processing!(
        generation: generation,
        job_id: job_id,
        next_job: next_job,
        status: "embedding",
        attributes: outcome_attributes
      )
      return job_id unless handed_off

      @job_id_for_failure = next_job.job_id
      begin
        next_job.enqueue
      rescue
        document.update_current_processing!(
          generation: generation,
          job_id: next_job.job_id,
          attributes: {
            status: "failed",
            processing_job_id: job_id,
            processing_job_execution: executions
          }
        )
        @job_id_for_failure = job_id
        raise
      end
      next_job.job_id
    else
      attributes = outcome_attributes.merge(status: "processed")
      document.complete_current_processing!(generation: generation, job_id: job_id, attributes: attributes)
      job_id
    end
  end

  def eligible_image_refs(document)
    document.extracted_content.fetch("sections", []).each_with_index.filter_map do |section, index|
      next unless section["type"] == "image_ref" && section["skipped_reason"] != "too_small"

      [ index, "image_ref:#{index}", section ]
    end
  end

  def build_enrichment_results(document, generation, image_refs, vision)
    chunks = []
    outcomes = []

    image_refs.each do |_, source_key, image_ref|
      break unless document.processing_stage_current?(generation: generation, job_id: job_id)

      description = begin
        vision.describe_image_from_document(document, image_ref)
      rescue Enrichment::OpenAiVisionService::PermanentImageError => e
        Rails.logger.warn do
          "EnrichDocumentJob: permanent image failure document=#{document.id} " \
            "source_key=#{source_key} code=#{e.code}"
        end
        outcomes << image_outcome(source_key, status: "failed", error_code: e.code)
        next
      end

      if description.blank?
        outcomes << image_outcome(source_key, status: "failed", error_code: "empty_description")
        next
      end

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
      outcomes << image_outcome(source_key, status: "succeeded")
    end

    [ chunks, outcomes ]
  end

  def persist_enrichment_results(document, generation, chunks, outcomes)
    document.with_lock do
      document.reload
      return false unless document.processing_generation == generation.to_i && document.processing_job_id == job_id

      extracted_content = document.extracted_content.deep_dup
      outcomes.each do |outcome|
        section = extracted_content.fetch("sections", [])[outcome[:section_index]]
        next unless section

        section["enrichment"] = {
          "status" => outcome[:status],
          "error_code" => outcome[:error_code]
        }.compact
      end

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

      document.update_columns(
        extracted_content: extracted_content,
        chunk_count: document.document_chunks.count
      )
      true
    end
  end

  def finish_recorded_outcome(document, generation, image_refs)
    document.reload
    outcome = recorded_enrichment_outcome(document, image_refs)

    if outcome == "failed"
      document.complete_current_processing!(
        generation: generation,
        job_id: job_id,
        attributes: {
          status: "processed",
          enrichment_status: "failed",
          enriched_at: Time.current
        }
      )
      job_id
    else
      continue_to_embedding(document, generation, enrichment_status: outcome)
    end
  end

  def recorded_enrichment_outcome(document, image_refs)
    sections = document.extracted_content.fetch("sections", [])
    statuses = image_refs.map { |index, _, _| sections[index]&.dig("enrichment", "status") }

    return "succeeded" if statuses.all?("succeeded")
    return "skipped" if statuses.all?("skipped")
    return "failed" if statuses.all?("failed")

    "partial"
  end

  def terminal_image_outcome?(section)
    section.dig("enrichment", "status").in?(%w[succeeded skipped failed])
  end

  def image_outcome(source_key, status:, error_code: nil)
    {
      section_index: source_key.delete_prefix("image_ref:").to_i,
      status: status,
      error_code: error_code
    }
  end

  def finalize_exhausted_enrichment(error)
    document_id, generation = arguments
    document = Document.find_by(id: document_id)
    return unless document

    image_refs = eligible_image_refs(document)
    outcome = if image_refs.any? && image_refs.all? { |_, _, section| terminal_image_outcome?(section) }
      recorded_enrichment_outcome(document, image_refs)
    else
      "failed"
    end

    completed = document.complete_current_processing!(
      generation: generation,
      job_id: job_id,
      attributes: {
        status: "processed",
        enrichment_status: outcome,
        enriched_at: Time.current
      }
    )
    return unless completed

    Rails.logger.warn do
      "EnrichDocumentJob: enrichment ended without completion document=#{document_id} " \
        "error=#{error.class}"
    end
  end
end
