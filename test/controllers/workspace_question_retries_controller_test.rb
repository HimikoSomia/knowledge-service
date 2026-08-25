require "test_helper"

class WorkspaceQuestionRetriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @workspace = workspaces(:workspace_one)
    @question = @workspace.workspace_questions.create!(
      user: @user,
      question: "Retry this question",
      status: "failed",
      error_code: "provider_unavailable"
    )
    sign_in_as(@user)
  end

  test "owner can retry a failed question" do
    assert_enqueued_jobs 1, only: AnswerWorkspaceQuestionJob do
      post workspace_question_retry_path(@workspace, @question)
    end

    assert_redirected_to workspace_question_path(@workspace, @question)
    assert @question.reload.pending?
    assert_nil @question.error_code
  end

  test "owner can retry a failed question through JSON" do
    post workspace_question_retry_path(@workspace, @question), as: :json

    assert_response :accepted
    assert_equal "pending", response.parsed_body["status"]
    assert_nil response.parsed_body["error_code"]
  end

  test "does not retry a question that is not failed" do
    @question.update_columns(status: "answered", answer: "Complete")

    assert_no_enqueued_jobs do
      post workspace_question_retry_path(@workspace, @question), as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "not_retryable", response.parsed_body["error"]
  end

  test "cannot retry another user's question" do
    other_workspace = workspaces(:workspace_two)
    other_question = other_workspace.workspace_questions.create!(
      user: users(:two), question: "Private", status: "failed"
    )

    assert_no_enqueued_jobs do
      post workspace_question_retry_path(other_workspace, other_question), as: :json
    end

    assert_response :not_found
    assert other_question.reload.failed?
  end

  test "a repeated retry request does not queue a second job" do
    assert_enqueued_jobs 1, only: AnswerWorkspaceQuestionJob do
      post workspace_question_retry_path(@workspace, @question), as: :json
      assert_response :accepted

      post workspace_question_retry_path(@workspace, @question), as: :json
      assert_response :unprocessable_entity
    end

    assert @question.reload.pending?
  end

  test "records queue failure when a retry cannot be enqueued" do
    unavailable_job = Object.new
    unavailable_job.define_singleton_method(:job_id) { "unavailable-retry-job" }
    unavailable_job.define_singleton_method(:enqueue) { raise "queue unavailable" }

    with_stubbed_answer_job(unavailable_job) do
      post workspace_question_retry_path(@workspace, @question), as: :json
    end

    assert_response :service_unavailable
    assert @question.reload.failed?
    assert_equal "queue_unavailable", @question.error_code
  end

  private

  def with_stubbed_answer_job(job)
    AnswerWorkspaceQuestionJob.define_singleton_method(:new) { |*| job }
    yield
  ensure
    AnswerWorkspaceQuestionJob.singleton_class.remove_method(:new)
  end
end
