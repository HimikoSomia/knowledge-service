require "application_system_test_case"

class WorkspaceQuestionsTest < ApplicationSystemTestCase
  Context = Retrieval::WorkspaceRetriever::Result

  setup do
    @user = users(:one)
    @workspace = workspaces(:workspace_one)
    sign_in_through_browser_as(@user)
  end

  test "generates and displays a grounded answer with its citation" do
    visit workspace_questions_path(@workspace)
    fill_in "workspace_question_question", with: "What result is documented?"
    click_button "Send"

    assert_text "What result is documented?"
    assert_text "Searching workspace knowledge"

    perform_answer_jobs(answer: "The documented result is 42 [1].")
    refresh

    assert_text "The documented result is 42 [1]."
    assert_selector "[id^='source-1-question-']", text: "Processed Document"
    assert_selector "[id^='source-1-question-']", text: "Page 1"
    assert_selector "[id^='source-1-question-']", text: "The documented result is 42."

    question = @workspace.workspace_questions.find_by!(question: "What result is documented?")
    assert question.answered?
    assert_equal "browser-test-model", question.answer_model
    assert_equal "Processed Document", question.citations.first["title"]
  end

  test "retries a failed question and displays the completed answer" do
    question = @workspace.workspace_questions.create!(
      user: @user,
      question: "Can this answer be retried?",
      status: "failed",
      error_code: "provider_unavailable"
    )

    visit workspace_questions_path(@workspace)
    click_button "Retry answer"

    assert_text "Answer generation was queued again."
    assert_text "Searching workspace knowledge"

    perform_answer_jobs(answer: "The retry completed successfully [1].")
    refresh

    assert_text "The retry completed successfully [1]."
    assert_selector "#source-1-question-#{question.id}", text: "Processed Document"
    assert question.reload.answered?
    assert_nil question.error_code
  end

  private

  def perform_answer_jobs(answer:)
    contexts = [ browser_context ]
    retriever = Object.new
    retriever.define_singleton_method(:retrieve) { |_| contexts }

    generator = Object.new
    generator.define_singleton_method(:generate) do |question:, contexts:|
      raise "Unexpected browser-test question" if question.blank?
      raise "Unexpected browser-test context" unless contexts.one?

      Answering::OpenAiAnswerService::Result.new(
        answer: answer,
        model: "browser-test-model",
        insufficient_context: false
      )
    end

    with_stubbed_constructor(Retrieval::WorkspaceRetriever, retriever) do
      with_stubbed_constructor(Answering::OpenAiAnswerService, generator) do
        perform_enqueued_jobs(only: AnswerWorkspaceQuestionJob)
      end
    end
  end

  def with_stubbed_constructor(klass, instance)
    klass.define_singleton_method(:new) { |*| instance }
    yield
  ensure
    klass.singleton_class.remove_method(:new)
  end

  def browser_context
    Context.new(
      chunk_id: document_chunks(:chunk_one).id,
      content: "The documented result is 42.",
      source_type: "document",
      source_id: documents(:processed_doc).id,
      source_title: "Processed Document",
      source_locator: "Page 1",
      metadata: {},
      distance: 0.1
    )
  end
end
