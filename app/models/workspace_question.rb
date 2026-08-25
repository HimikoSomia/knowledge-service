class WorkspaceQuestion < ApplicationRecord
  STATUSES = {
    pending: "pending",
    answering: "answering",
    answered: "answered",
    insufficient_context: "insufficient_context",
    failed: "failed"
  }.freeze

  MAX_QUESTION_LENGTH = 2_000

  belongs_to :workspace
  belongs_to :user

  enum :status, STATUSES, validate: true

  validates :question, presence: true, length: { maximum: MAX_QUESTION_LENGTH }
  validate :workspace_and_user_have_same_owner

  scope :recent_first, -> { order(created_at: :desc) }

  def enqueue_answer!
    enqueue_answer_from!("pending")
  end

  def retry_answer!
    enqueue_answer_from!("failed")
  end

  def claim_answering!(job_id:, execution:)
    with_lock do
      first_delivery = pending? && answer_job_id == job_id && answer_job_execution.zero?
      retry_delivery = answering? && answer_job_id == job_id && execution > answer_job_execution
      return false unless first_delivery || retry_delivery

      update_columns(
        status: "answering",
        answer_job_execution: execution,
        error_code: nil
      )
      true
    end
  end

  def complete_answer!(job_id:, status:, answer:, citations:, model: nil)
    with_lock do
      return false unless answer_job_id == job_id && answering?

      update_columns(
        status: status,
        answer: answer,
        citations: citations,
        answer_model: model,
        error_code: nil,
        answered_at: Time.current,
        answer_job_id: nil,
        answer_job_execution: 0
      )
      true
    end
  end

  def fail_answer!(job_id:, error_code:)
    with_lock do
      return false unless answer_job_id == job_id && answering?

      update_columns(
        status: "failed",
        error_code: error_code,
        answer_job_id: nil,
        answer_job_execution: 0
      )
      true
    end
  end

  private

  def enqueue_answer_from!(required_status)
    job = AnswerWorkspaceQuestionJob.new(id)

    with_lock do
      return false unless status == required_status

      update_columns(
        status: "pending",
        answer: nil,
        citations: [],
        answer_model: nil,
        error_code: nil,
        answered_at: nil,
        answer_job_id: job.job_id,
        answer_job_execution: 0
      )
    end

    job.enqueue
    true
  rescue => e
    with_lock do
      if answer_job_id == job&.job_id
        update_columns(status: "failed", error_code: "queue_unavailable")
      end
    end
    Rails.logger.error "WorkspaceQuestion #{id} answer enqueue failed (#{e.class})"
    false
  end

  def workspace_and_user_have_same_owner
    return if workspace.blank? || user.blank?
    return if workspace.user == user

    errors.add(:workspace, "must belong to the same user as the question")
  end
end
