class Retrieval::WorkspaceRetriever
  ConfigurationError = Class.new(StandardError)
  TransientError = Class.new(StandardError)

  Result = Data.define(
    :chunk_id,
    :content,
    :source_type,
    :source_id,
    :source_title,
    :source_locator,
    :metadata,
    :distance
  )

  DEFAULT_LIMIT = 8
  DEFAULT_CANDIDATE_LIMIT = 24
  DEFAULT_MAX_DISTANCE = 0.55
  DEFAULT_MAX_CONTEXT_CHARS = 16_000
  DEFAULT_MAX_RESULTS_PER_SOURCE = 3

  def initialize(user, workspace, search_service: Retrieval::WorkspaceKnowledgeSearchService.new(user))
    @user = user
    @workspace = workspace
    @search_service = search_service
  end

  def retrieve(question, limit: DEFAULT_LIMIT)
    raise ArgumentError, "Question cannot be blank" if question.to_s.strip.blank?
    raise ActiveRecord::RecordNotFound unless workspace.user_id == user.id

    source_counts = Hash.new(0)
    context_chars = 0
    results = []

    candidates(question).each do |chunk|
      distance = chunk.neighbor_distance.to_f
      next if distance > max_distance
      source_key = [ chunk.source_type, chunk.source_id ]
      next if source_counts[source_key] >= max_results_per_source
      break if results.size >= limit

      content = chunk.content.to_s.strip
      next if content.blank?
      next if context_chars + content.length > max_context_chars

      results << build_result(chunk, distance)
      source_counts[source_key] += 1
      context_chars += content.length
    end

    results
  rescue Retrieval::WorkspaceKnowledgeSearchService::NotConfiguredError,
         Embedding::OpenAiEmbeddingService::ConfigurationError => e
    raise ConfigurationError, e.message
  rescue Embedding::OpenAiEmbeddingService::RateLimitError,
         Embedding::OpenAiEmbeddingService::ServiceError => e
    raise TransientError, e.message
  end

  private

  attr_reader :user, :workspace, :search_service

  def candidates(question)
    search_service.search(
      question.to_s.strip,
      workspace_id: workspace.id,
      limit: candidate_limit
    )
  end

  def build_result(chunk, distance)
    Result.new(
      chunk_id: chunk.chunk_id,
      content: chunk.content,
      source_type: chunk.source_type,
      source_id: chunk.source_id,
      source_title: chunk.source_title,
      source_locator: chunk.source_locator,
      metadata: chunk.metadata,
      distance: distance
    )
  end

  def candidate_limit
    positive_integer_env("WORKSPACE_QA_CANDIDATE_LIMIT", DEFAULT_CANDIDATE_LIMIT)
  end

  def max_context_chars
    positive_integer_env("WORKSPACE_QA_MAX_CONTEXT_CHARS", DEFAULT_MAX_CONTEXT_CHARS)
  end

  def max_results_per_source
    positive_integer_env("WORKSPACE_QA_MAX_RESULTS_PER_SOURCE", DEFAULT_MAX_RESULTS_PER_SOURCE)
  end

  def max_distance
    Float(ENV.fetch("WORKSPACE_QA_MAX_DISTANCE", DEFAULT_MAX_DISTANCE.to_s))
  rescue ArgumentError
    DEFAULT_MAX_DISTANCE
  end

  def positive_integer_env(name, default)
    value = Integer(ENV.fetch(name, default.to_s))
    value.positive? ? value : default
  rescue ArgumentError
    default
  end
end
