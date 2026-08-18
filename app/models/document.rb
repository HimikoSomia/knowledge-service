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

  MAX_FILE_SIZE = 50.megabytes

  has_one_attached :file
  belongs_to :user
  has_many :document_workspaces, dependent: :destroy
  has_many :workspaces, through: :document_workspaces
  has_many :document_chunks, dependent: :destroy

  enum :status, STATUSES, validate: true

  validates :title, presence: true
  validate :file_must_be_attached, on: :create
  validate :file_content_type_supported, if: -> { file.attached? }
  validate :file_size_within_limit, if: -> { file.attached? }

  before_save :detect_document_type

  after_commit :enqueue_processing_job, on: :create
  after_commit :enqueue_reprocessing_if_file_replaced, on: :update

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
    ProcessDocumentJob.perform_later(id) if file.attached?
  end

  def enqueue_reprocessing_if_file_replaced
    return unless file.attached?

    new_checksum = file.blob.checksum

    if file_checksum.blank?
      return unless failed?
    else
      return if file_checksum == new_checksum
    end

    update_columns(
      status: "pending",
      processing_started_at: nil,
      processed_at: nil,
      enriched_at: nil,
      embedded_at: nil,
      error_message: nil
    )
    ProcessDocumentJob.perform_later(id)
  end
end
