class KnowledgeSource < ApplicationRecord
  SOURCE_TYPES = {
    note: "note",
    memo: "memo"
  }.freeze

  STATUSES = {
    pending: "pending",
    indexing: "indexing",
    ready: "ready",
    unindexed: "unindexed",
    failed: "failed"
  }.freeze

  MAX_TITLE_LENGTH = 200
  MAX_CONTENT_LENGTH = 100_000

  belongs_to :workspace
  belongs_to :user
  has_many :knowledge_chunks, dependent: :destroy

  enum :source_type, SOURCE_TYPES, validate: true
  enum :status, STATUSES, validate: true

  validates :title, presence: true, length: { maximum: MAX_TITLE_LENGTH }
  validates :content, presence: true, length: { maximum: MAX_CONTENT_LENGTH }
  validate :workspace_and_user_have_same_owner

  scope :recent_first, -> { order(updated_at: :desc) }

  def enqueue_indexing!
    job = nil

    with_lock do
      generation = indexing_generation + 1
      job = IndexKnowledgeSourceJob.new(id, generation)
      update_columns(
        status: "pending",
        error_code: nil,
        indexed_at: nil,
        indexing_generation: generation,
        indexing_job_id: job.job_id,
        indexing_job_execution: 0
      )
    end

    enqueued_job = job.enqueue
    raise ActiveJob::EnqueueError, "Knowledge source indexing was not enqueued" unless enqueued_job

    true
  rescue => error
    with_lock do
      if job && indexing_job_id == job.job_id
        update_columns(
          status: "failed",
          error_code: "queue_unavailable",
          indexing_job_id: nil,
          indexing_job_execution: 0
        )
      end
    end
    Rails.logger.error "KnowledgeSource #{id} indexing enqueue failed (#{error.class})"
    false
  end

  def claim_indexing!(generation:, job_id:, execution:)
    with_lock do
      return false unless indexing_generation == generation.to_i && indexing_job_id == job_id

      first_delivery = pending? && indexing_job_execution.zero?
      retry_delivery = indexing? && execution > indexing_job_execution
      return false unless first_delivery || retry_delivery

      update_columns(status: "indexing", indexing_job_execution: execution, error_code: nil)
      true
    end
  end

  def complete_indexing!(generation:, job_id:, chunks:, model:)
    with_lock do
      return false unless current_indexing_job?(generation, job_id)

      knowledge_chunks.delete_all
      now = Time.current
      records = chunks.each_with_index.map do |chunk, index|
        {
          knowledge_source_id: id,
          chunk_index: index,
          content: chunk.fetch(:content),
          content_checksum: chunk.fetch(:content_checksum),
          token_count: chunk.fetch(:token_count),
          embedding: chunk.fetch(:embedding),
          embedding_model: model,
          metadata: chunk.fetch(:metadata, {}),
          created_at: now,
          updated_at: now
        }
      end
      KnowledgeChunk.insert_all!(records)

      update_columns(
        status: "ready",
        error_code: nil,
        indexed_at: now,
        indexing_job_id: nil,
        indexing_job_execution: 0
      )
      true
    end
  end

  def mark_unindexed!(generation:, job_id:, error_code: "not_configured")
    finish_indexing!(
      generation: generation,
      job_id: job_id,
      status: "unindexed",
      error_code: error_code,
      discard_chunks: true
    )
  end

  def fail_indexing!(generation:, job_id:, error_code:)
    finish_indexing!(
      generation: generation,
      job_id: job_id,
      status: "failed",
      error_code: error_code,
      discard_chunks: false
    )
  end

  private

  def finish_indexing!(generation:, job_id:, status:, error_code:, discard_chunks:)
    with_lock do
      return false unless current_indexing_job?(generation, job_id)

      knowledge_chunks.delete_all if discard_chunks
      update_columns(
        status: status,
        error_code: error_code,
        indexed_at: nil,
        indexing_job_id: nil,
        indexing_job_execution: 0
      )
      true
    end
  end

  def current_indexing_job?(generation, job_id)
    indexing_generation == generation.to_i && indexing_job_id == job_id && indexing?
  end

  def workspace_and_user_have_same_owner
    return if workspace.blank? || user.blank?
    return if workspace.user == user

    errors.add(:workspace, "must belong to the same user as the knowledge source")
  end
end
