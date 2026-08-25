require "test_helper"

class WorkspaceQuestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @workspace = workspaces(:workspace_one)
    sign_in_as(@user)
  end

  test "creates an owned question and queues its answer" do
    assert_enqueued_with(job: AnswerWorkspaceQuestionJob) do
      assert_difference -> { @workspace.workspace_questions.count }, 1 do
        post workspace_questions_path(@workspace),
             params: { workspace_question: { question: "What is documented?" } }
      end
    end

    question = @workspace.workspace_questions.recent_first.first
    assert_redirected_to workspace_question_path(@workspace, question)
    assert_equal @user, question.user
    assert question.pending?
  end

  test "creates a question through JSON and returns accepted" do
    post workspace_questions_path(@workspace),
         params: { workspace_question: { question: "What is documented?" } },
         as: :json

    assert_response :accepted
    payload = response.parsed_body
    assert_equal "pending", payload["status"]
    assert_equal "What is documented?", payload["question"]
    assert_equal @workspace.id, payload["workspace_id"]
  end

  test "rejects a blank question in HTML" do
    assert_no_difference -> { WorkspaceQuestion.count } do
      post workspace_questions_path(@workspace),
           params: { workspace_question: { question: "" } }
    end

    assert_response :unprocessable_entity
    assert_select "#question_error_explanation"
  end

  test "rejects a blank question through JSON" do
    post workspace_questions_path(@workspace),
         params: { workspace_question: { question: "" } },
         as: :json

    assert_response :unprocessable_entity
    assert response.parsed_body.dig("errors", "question").present?
  end

  test "rejects an oversized question through JSON" do
    post workspace_questions_path(@workspace),
         params: {
           workspace_question: {
             question: "x" * (WorkspaceQuestion::MAX_QUESTION_LENGTH + 1)
           }
         },
         as: :json

    assert_response :unprocessable_entity
    assert response.parsed_body.dig("errors", "question").present?
  end

  test "shows an answered question and citations" do
    question = answered_question

    get workspace_question_path(@workspace, question)

    assert_response :success
    assert_select "h2", "Answer"
    assert_match "Grounded answer", response.body
    assert_match "Processed Document", response.body
  end

  test "shows a question as JSON" do
    question = answered_question

    get workspace_question_path(@workspace, question, format: :json)

    assert_response :success
    assert_equal "answered", response.parsed_body["status"]
    assert_equal 1, response.parsed_body["citations"].size
  end

  test "cannot create a question in another user's workspace" do
    assert_no_difference -> { WorkspaceQuestion.count } do
      post workspace_questions_path(workspaces(:workspace_two)),
           params: { workspace_question: { question: "Reveal private data" } }
    end

    assert_response :not_found
  end

  test "cannot read another user's question" do
    other = workspaces(:workspace_two).workspace_questions.create!(
      user: users(:two), question: "Private question"
    )

    get workspace_question_path(workspaces(:workspace_two), other, format: :json)

    assert_response :not_found
  end

  private

  def answered_question
    @workspace.workspace_questions.create!(
      user: @user,
      question: "What is documented?",
      status: "answered",
      answer: "Grounded answer [1].",
      answer_model: "test-model",
      answered_at: Time.current,
      citations: [
        {
          "number" => 1,
          "source_type" => "document",
          "source_id" => documents(:processed_doc).id,
          "chunk_id" => document_chunks(:chunk_one).id,
          "title" => "Processed Document",
          "locator" => "Page 1",
          "excerpt" => "Relevant excerpt",
          "distance" => 0.1
        }
      ]
    )
  end
end
