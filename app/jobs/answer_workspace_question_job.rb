class AnswerWorkspaceQuestionJob < ApplicationJob
  queue_as :answers

  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, _error|
    job.send(:finalize_failure, "unexpected_failure")
  end
  retry_on Retrieval::WorkspaceRetriever::TransientError,
           Answering::OpenAiAnswerService::TransientError,
           wait: :polynomially_longer,
           attempts: 5 do |job, _error|
    job.send(:finalize_failure, "provider_unavailable")
  end
  discard_on Retrieval::WorkspaceRetriever::ConfigurationError,
             Answering::OpenAiAnswerService::ConfigurationError do |job, _error|
    job.send(:finalize_failure, "not_configured")
  end
  discard_on Answering::OpenAiAnswerService::PermanentError do |job, _error|
    job.send(:finalize_failure, "invalid_response")
  end
  discard_on ActiveRecord::RecordNotFound

  def perform(workspace_question_id)
    question = WorkspaceQuestion.find(workspace_question_id)
    claimed = question.claim_answering!(job_id: job_id, execution: executions)
    return unless claimed

    contexts = workspace_retriever(question).retrieve(question.question)
    if contexts.empty?
      question.complete_answer!(
        job_id: job_id,
        status: "insufficient_context",
        answer: "This workspace does not contain enough relevant information to answer that question.",
        citations: []
      )
      return
    end

    generated = answer_service.generate(question: question.question, contexts: contexts)
    if generated.insufficient_context
      question.complete_answer!(
        job_id: job_id,
        status: "insufficient_context",
        answer: generated.answer,
        citations: [],
        model: generated.model
      )
      return
    end

    question.complete_answer!(
      job_id: job_id,
      status: "answered",
      answer: generated.answer,
      citations: citation_snapshots(contexts, generated.answer),
      model: generated.model
    )
  end

  private

  def workspace_retriever(question)
    Retrieval::WorkspaceRetriever.new(question.user, question.workspace)
  end

  def answer_service
    Answering::OpenAiAnswerService.new
  end

  def citation_snapshots(contexts, answer)
    cited_numbers = answer.scan(/\[(\d+)\]/).flatten.map(&:to_i).uniq

    contexts.each_with_index.filter_map do |context, index|
      next unless cited_numbers.include?(index + 1)

      {
        "number" => index + 1,
        "source_type" => context.source_type,
        "source_id" => context.source_id,
        "chunk_id" => context.chunk_id,
        "title" => context.source_title,
        "locator" => context.source_locator,
        "excerpt" => context.content.to_s.truncate(500),
        "distance" => context.distance
      }
    end
  end

  def finalize_failure(error_code)
    question = WorkspaceQuestion.find_by(id: arguments.first)
    question&.fail_answer!(job_id: job_id, error_code: error_code)
  end
end
