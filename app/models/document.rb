class Document < ApplicationRecord
  STATUSES = {
    pending: "pending",
    processing: "processing",
    enriching: "enriching",
    embedding: "embedding",
    processed: "processed",
    ready: "ready",
    failed: "failed"
  }.freeze

  ENRICHMENT_STATUSES = {
    not_required: "not_required",
    pending: "pending",
    in_progress: "in_progress",
    succeeded: "succeeded",
    skipped: "skipped",
    partial: "partial",
    failed: "failed"
  }.freeze

  MAX_FILE_SIZE = 50.megabytes

  has_one_attached :file
  belongs_to :user
  has_many :document_workspaces, dependent: :destroy
  has_many :workspaces, through: :document_workspaces
  has_many :document_chunks, dependent: :destroy

  enum :status, STATUSES, validate: true
  enum :enrichment_status, ENRICHMENT_STATUSES, prefix: :enrichment, validate: true

  validates :title, presence: true
  validate :file_must_be_attached, on: :create
  validate :file_content_type_supported, if: -> { file.attached? }
  validate :file_size_within_limit, if: -> { file.attached? }

  before_save :detect_document_type

  after_commit :enqueue_processing_job, on: :create
  after_commit :enqueue_reprocessing_if_file_replaced, on: :update

  # Claims a processing stage for one Active Job execution. A queued stage is
  # won by its first delivery; only a later execution of that same job may
  # reclaim a failed or interrupted stage. This prevents duplicate deliveries
  # from running provider calls or replacing chunks concurrently.
  def claim_processing_stage!(generation:, job_id:, execution:, queued_status:, running_status:)
    with_lock do
      return false unless current_processing_generation?(generation)

      first_delivery = Array(queued_status).include?(status) && processing_job_execution.zero?
      retry_delivery = processing_job_id == job_id &&
                       execution > processing_job_execution &&
                       (status == running_status || failed?)
      return false unless first_delivery || retry_delivery

      attributes = {
        status: running_status,
        processing_job_id: job_id,
        processing_job_execution: execution,
        error_message: nil
      }
      attributes[:processing_started_at] = Time.current if running_status == "processing"
      update_columns(attributes)
      true
    end
  end

  def processing_stage_current?(generation:, job_id:)
    reload
    current_processing_generation?(generation) && processing_job_id == job_id
  end

  def update_current_processing!(generation:, job_id:, attributes:)
    with_lock do
      return false unless current_processing_generation?(generation) && processing_job_id == job_id

      update_columns(attributes)
      true
    end
  end

  def handoff_processing!(generation:, job_id:, next_job:, status:, attributes: {})
    with_lock do
      return false unless current_processing_generation?(generation) && processing_job_id == job_id

      update_columns(attributes.merge(
        status: status,
        processing_job_id: next_job.job_id,
        processing_job_execution: 0,
        error_message: nil
      ))
      true
    end
  end

  def complete_current_processing!(generation:, job_id:, attributes:)
    update_current_processing!(
      generation: generation,
      job_id: job_id,
      attributes: attributes.merge(processing_job_id: nil, processing_job_execution: 0, error_message: nil)
    )
  end

  def fail_current_processing!(generation:, job_id:, message:)
    update_current_processing!(
      generation: generation,
      job_id: job_id,
      attributes: { status: "failed", error_message: message.to_s.truncate(1000) }
    )
  end

  def mark_processing!
    update_columns(status: "processing", processing_started_at: Time.current, error_message: nil)
  end

  def record_extraction!(chunk_count_value, checksum)
    update_columns(
      processed_at: Time.current,
      chunk_count: chunk_count_value,
      file_checksum: checksum,
      error_message: nil
    )
  end

  def mark_enriching!
    update_columns(status: "enriching")
  end

  def mark_enriched!
    update_columns(enriched_at: Time.current)
  end

  def mark_embedding!
    update_columns(status: "embedding")
  end

  def mark_processed!
    update_columns(status: "processed")
  end

  def mark_ready!
    update_columns(status: "ready", embedded_at: Time.current, error_message: nil)
  end

  def mark_failed!(message)
    update_columns(status: "failed", error_message: message.to_s.truncate(1000))
  end

  def already_processed_for?(checksum)
    (processed? || ready?) && file_checksum == checksum
  end

  private

  def detect_document_type
    return unless file.attached?

    self.document_type = Extraction::DocumentExtractor.document_type_for(file.blob) || "unknown"
  end

  def file_must_be_attached
    errors.add(:file, :blank) unless file.attached?
  end

  def file_content_type_supported
    return if Extraction::DocumentExtractor.supported?(file.blob)

    errors.add(
      :file,
      "type “#{file.blob.content_type}” is not supported. " \
      "Please upload a PDF, DOCX, spreadsheet, PPTX, text file, or image."
    )
  end

  def file_size_within_limit
    return if file.blob.byte_size <= MAX_FILE_SIZE

    max_mb = (MAX_FILE_SIZE / 1.megabyte).to_i
    errors.add(:file, "is too large. The maximum allowed size is #{max_mb} MB.")
  end

  def enqueue_processing_job
    enqueue_processing_for_current_file if file.attached?
  end

  def enqueue_reprocessing_if_file_replaced
    return unless file.attached?

    new_checksum = file.blob.checksum
    return if processing_checksum == new_checksum && !failed?

    enqueue_processing_for_current_file
  end

  def enqueue_processing_for_current_file
    checksum = file.blob.checksum
    generation = nil
    job = nil

    with_lock do
      return if processing_checksum == checksum && !failed?

      generation = processing_generation + 1
      job = ProcessDocumentJob.new(id, generation)
      update_columns(
        status: "pending",
        processing_generation: generation,
        processing_checksum: checksum,
        processing_job_id: job.job_id,
        processing_job_execution: 0,
        processing_started_at: nil,
        processed_at: nil,
        enriched_at: nil,
        enrichment_status: "not_required",
        embedded_at: nil,
        error_message: nil
      )
    end

    job.enqueue
  rescue => e
    if job
      fail_current_processing!(
        generation: generation,
        job_id: job.job_id,
        message: "Document processing could not be queued. Please try again."
      )
    end
    Rails.logger.error "Document #{id} processing enqueue failed (#{e.class})"
    raise
  end

  def current_processing_generation?(generation)
    generation.present? ? processing_generation == generation : processing_generation.zero?
  end
end
