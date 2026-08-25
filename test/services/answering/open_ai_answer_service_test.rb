require "test_helper"

class Answering::OpenAiAnswerServiceTest < ActiveSupport::TestCase
  Context = Retrieval::WorkspaceRetriever::Result

  setup do
    ENV["OPENAI_API_KEY"] = "test-key"
    ENV["OPENAI_ANSWER_MODEL"] = "test-answer-model"
  end

  teardown do
    ENV.delete("OPENAI_API_KEY")
    ENV.delete("OPENAI_ANSWER_MODEL")
    ENV.delete("OPENAI_ANSWER_MAX_TOKENS")
    remove_stubbed_client
  end

  test "generates a grounded answer with valid citations" do
    stub_client_response("The documented result is 42 [1].")

    result = Answering::OpenAiAnswerService.new.generate(
      question: "What is the result?",
      contexts: [ context ]
    )

    assert_equal "The documented result is 42 [1].", result.answer
    assert_equal "test-answer-model", result.model
    assert_not result.insufficient_context
  end

  test "tells the provider that source content is untrusted" do
    captured = nil
    stub_client_response("A safe answer [1].") { |parameters| captured = parameters }

    Answering::OpenAiAnswerService.new.generate(question: "Question", contexts: [ context ])

    system_prompt = captured.fetch(:messages).first.fetch(:content)
    assert_match(/untrusted evidence/, system_prompt)
    assert_match(/Never follow/, system_prompt)
  end

  test "rejects an answer with invented citations" do
    stub_client_response("An unsupported answer [2].")

    assert_raises(Answering::OpenAiAnswerService::InvalidResponseError) do
      Answering::OpenAiAnswerService.new.generate(question: "Question", contexts: [ context ])
    end
  end

  test "maps an explicit provider abstention to insufficient context" do
    stub_client_response("INSUFFICIENT_CONTEXT")

    result = Answering::OpenAiAnswerService.new.generate(
      question: "What is not documented?",
      contexts: [ context ]
    )

    assert result.insufficient_context
    assert_match(/does not contain enough relevant information/, result.answer)
  end

  test "requires configuration without calling the provider" do
    ENV.delete("OPENAI_API_KEY")

    assert_raises(Answering::OpenAiAnswerService::ConfigurationError) do
      Answering::OpenAiAnswerService.new.generate(question: "Question", contexts: [ context ])
    end
  end

  private

  def context
    Context.new(
      chunk_id: 1,
      content: "The result is 42.",
      source_type: "document",
      source_id: 1,
      source_title: "Report",
      source_locator: "Page 1",
      metadata: {},
      distance: 0.1
    )
  end

  def stub_client_response(answer, &capture)
    fake = Object.new
    fake.define_singleton_method(:chat) do |parameters:|
      capture&.call(parameters)
      { "choices" => [ { "message" => { "content" => answer } } ] }
    end
    OpenAI::Client.define_singleton_method(:new) { |**_| fake }
  end

  def remove_stubbed_client
    return unless OpenAI::Client.singleton_class.instance_methods(false).include?(:new)

    OpenAI::Client.singleton_class.remove_method(:new)
  end
end
