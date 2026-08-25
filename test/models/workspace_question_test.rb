require "test_helper"

class WorkspaceQuestionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @workspace = workspaces(:workspace_one)
  end

  test "is valid for the workspace owner" do
    question = @workspace.workspace_questions.new(user: @user, question: "What is documented?")
    assert question.valid?
  end

  test "requires a question within the length limit" do
    question = @workspace.workspace_questions.new(user: @user, question: "")
    assert_not question.valid?
    assert_includes question.errors[:question], "can't be blank"

    question.question = "x" * (WorkspaceQuestion::MAX_QUESTION_LENGTH + 1)
    assert_not question.valid?
    assert question.errors[:question].any?
  end

  test "rejects a workspace owned by another user" do
    question = workspaces(:workspace_two).workspace_questions.new(user: @user, question: "Private?")
    assert_not question.valid?
    assert_includes question.errors[:workspace], "must belong to the same user as the question"
  end

  test "claims one job delivery and rejects a duplicate" do
    question = create_question
    question.update_columns(answer_job_id: "answer-job")

    assert question.claim_answering!(job_id: "answer-job", execution: 1)
    assert_not question.claim_answering!(job_id: "answer-job", execution: 1)
    assert_not question.claim_answering!(job_id: "other-job", execution: 2)
    assert question.claim_answering!(job_id: "answer-job", execution: 2)
  end

  test "completes only the currently claimed answer" do
    question = create_question
    question.update_columns(status: "answering", answer_job_id: "answer-job", answer_job_execution: 1)

    assert_not question.complete_answer!(
      job_id: "other-job", status: "answered", answer: "Wrong", citations: []
    )
    assert question.complete_answer!(
      job_id: "answer-job",
      status: "answered",
      answer: "Grounded [1]",
      citations: [ { "number" => 1 } ],
      model: "answer-model"
    )

    question.reload
    assert question.answered?
    assert_equal "Grounded [1]", question.answer
    assert_nil question.answer_job_id
    assert_not_nil question.answered_at
  end

  private

  def create_question
    @workspace.workspace_questions.create!(user: @user, question: "What is documented?")
  end
end
