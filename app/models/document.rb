class Document < ApplicationRecord
  STATUSES = %w[pending processing processed failed].freeze
  ENRICHMENT_STATUSES = %w[not_applicable pending enriching enriched failed].freeze
  EMBEDDING_STATUSES  = %w[not_started not_applicable pending embedding embedded failed not_configured].freeze

  CONTENT_TYPE_MAP = {
    "text/plain" => "txt",
    "text/markdown" => "md",
    "text/csv" => "csv",
    "application/json" => "json",
    "text/html" => "html",
    "application/xhtml+xml" => "html",
    "application/xml" => "xml",
    "text/xml" => "xml",
    "application/pdf" => "pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => "docx",
    "application/msword" => "doc",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => "xlsx",
    "application/vnd.ms-excel" => "xls",
    "application/vnd.oasis.opendocument.spreadsheet" => "ods",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation" => "pptx",
    "application/vnd.ms-powerpoint" => "ppt",
    # Image files
    "image/jpeg"  => "jpeg",
    "image/jpg"   => "jpeg",
    "image/png"   => "png",
    "image/webp"  => "webp",
    "image/gif"   => "gif",
    "image/tiff"  => "tiff",
    "image/bmp"   => "bmp",
    "image/heic"  => "heic",
    "image/heif"  => "heif"
  }.freeze

  has_one_attached :file
  belongs_to :user
  has_many :document_workspaces, dependent: :destroy
  has_many :workspaces, through: :document_workspaces
  has_many :document_chunks, dependent: :destroy

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :file_must_be_attached, on: :create

  before_save :detect_document_type

  after_commit :enqueue_processing_job, on: :create
  after_commit :enqueue_reprocessing_if_file_replaced, on: :update

  STATUSES.each do |s|
    define_method(:"#{s}?") { status == s }
  end

  ENRICHMENT_STATUSES.each do |s|
    define_method(:"enrichment_#{s}?") { enrichment_status == s }
  end

  EMBEDDING_STATUSES.each do |s|
    define_method(:"embedding_#{s}?") { embedding_status == s }
  end

  def mark_processing!
    update_columns(status: "processing", processing_started_at: Time.current)
  end

  def mark_processed!(chunk_count_value, checksum, enrichment_status: "not_applicable", embedding_status: "not_started")
    update_columns(
      status: "processed",
      processed_at: Time.current,
      chunk_count: chunk_count_value,
      file_checksum: checksum,
      error_message: nil,
      enrichment_status: enrichment_status,
      embedding_status: embedding_status
    )
  end

  def mark_embedding!
    update_columns(embedding_status: "embedding")
  end

  def mark_embedded!
    update_columns(embedding_status: "embedded", embedded_at: Time.current)
  end

  def mark_embedding_failed!(message)
    update_columns(embedding_status: "failed", error_message: message.to_s.truncate(1000))
  end

  def mark_enriching!
    update_columns(enrichment_status: "enriching")
  end

  def mark_enriched!
    update_columns(enrichment_status: "enriched", enriched_at: Time.current)
  end

  def mark_failed!(message)
    update_columns(status: "failed", error_message: message.to_s.truncate(1000))
  end

  def mark_enrichment_failed!(message)
    update_columns(enrichment_status: "failed", error_message: message.to_s.truncate(1000))
  end

  def already_processed_for?(checksum)
    processed? && file_checksum == checksum
  end

  private

  def detect_document_type
    return unless file.attached?

    content_type = file.blob.content_type
    ext = File.extname(file.blob.filename.to_s).delete(".").downcase.presence
    self.document_type = CONTENT_TYPE_MAP[content_type] || ext || "unknown"
  end

  def file_must_be_attached
    errors.add(:file, :blank) unless file.attached?
  end

  def enqueue_processing_job
    ProcessDocumentJob.perform_later(id) if file.attached?
  end

  def enqueue_reprocessing_if_file_replaced
    return unless file.attached?
    return unless file_checksum.present?
    return if file.blob.checksum == file_checksum

    ProcessDocumentJob.perform_later(id)
  end
end
