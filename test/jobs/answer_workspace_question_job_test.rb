require "test_helper"

class AnswerWorkspaceQuestionJobTest < ActiveJob::TestCase
  Context = Retrieval::WorkspaceRetriever::Result

  setup do
    @question = workspaces(:workspace_one).workspace_questions.create!(
      user: users(:one),
      question: "What is the documented result?"
    )
  end

  test "stores a grounded answer and citation snapshots" do
    job = build_job(contexts: [ context ], answer: "The result is 42 [1].")

    job.perform_now

    @question.reload
    assert @question.answered?
    assert_equal "The result is 42 [1].", @question.answer
    assert_equal "test-answer-model", @question.answer_model
    assert_equal "Report", @question.citations.first["title"]
    assert_equal "Page 1", @question.citations.first["locator"]
  end

  test "records insufficient context without calling the answer provider" do
    answer_calls = 0
    job = build_job(contexts: [], answer: "unused", answer_calls: -> { answer_calls += 1 })

    job.perform_now

    assert @question.reload.insufficient_context?
    assert_equal 0, answer_calls
    assert_empty @question.citations
  end

  test "duplicate delivery does not generate a second answer" do
    answer_calls = 0
    job = build_job(
      contexts: [ context ],
      answer: "The result is 42 [1].",
      answer_calls: -> { answer_calls += 1 }
    )

    job.perform_now
    job.perform_now

    assert_equal 1, answer_calls
    assert @question.reload.answered?
  end

  test "configuration failure is safely recorded without retry" do
    job = build_job(contexts: [ context ], answer_error: Answering::OpenAiAnswerService::ConfigurationError.new)

    assert_no_enqueued_jobs { job.perform_now }

    assert @question.reload.failed?
    assert_equal "not_configured", @question.error_code
  end

  test "records provider abstention as insufficient context" do
    job = build_job(
      contexts: [ context ],
      answer: Answering::OpenAiAnswerService::INSUFFICIENT_CONTEXT_MESSAGE,
      insufficient_context: true
    )

    job.perform_now

    assert @question.reload.insufficient_context?
    assert_empty @question.citations
  end

  test "transient provider failure retries without losing the job claim" do
    job = build_job(
      contexts: [ context ],
      answer_error: Answering::OpenAiAnswerService::TransientError.new
    )

    assert_enqueued_jobs 1, only: AnswerWorkspaceQuestionJob do
      job.perform_now
    end

    @question.reload
    assert @question.answering?
    assert_equal job.job_id, @question.answer_job_id
  end

  private

  def build_job(contexts:, answer: nil, answer_error: nil, answer_calls: nil, insufficient_context: false)
    retriever = Object.new
    retriever.define_singleton_method(:retrieve) { |_| contexts }
    generator = Object.new
    generator.define_singleton_method(:generate) do |question:, contexts:|
      answer_calls&.call
      raise answer_error if answer_error

      Answering::OpenAiAnswerService::Result.new(
        answer: answer,
        model: "test-answer-model",
        insufficient_context: insufficient_context
      )
    end

    AnswerWorkspaceQuestionJob.new(@question.id).tap do |job|
      @question.update_columns(answer_job_id: job.job_id)
      job.define_singleton_method(:workspace_retriever) { |_| retriever }
      job.define_singleton_method(:answer_service) { generator }
    end
  end

  def context
    Context.new(
      chunk_id: 1,
      content: "The result is 42.",
      source_type: "document",
      source_id: documents(:processed_doc).id,
      source_title: "Report",
      source_locator: "Page 1",
      metadata: {},
      distance: 0.1
    )
  end
end
