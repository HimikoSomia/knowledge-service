require "openai"
require "json"

# Generates embeddings through OpenAI.
#
# Configuration (ENV or Rails credentials):
#   OPENAI_API_KEY              — required
#   OPENAI_EMBEDDING_MODEL      — default: "text-embedding-3-small"
#   OPENAI_EMBEDDING_DIMENSIONS — default: 1536 (must match DB vector(1536))
#   OPENAI_EMBEDDING_BATCH_SIZE — default: 100
#
# The selected model MUST produce exactly OPENAI_EMBEDDING_DIMENSIONS floats.
# Compatible defaults:
#   text-embedding-3-small  → 1536 (schema default) ✓
#   text-embedding-ada-002  → 1536                  ✓
#   text-embedding-3-large  → 3072 (needs migration) ✗
#
class Embedding::OpenAiEmbeddingService
  ConfigurationError = Class.new(StandardError)
  QuotaError = Class.new(ConfigurationError)
  RateLimitError = Class.new(StandardError)
  ServiceError = Class.new(StandardError)
  ValidationError = Class.new(StandardError)
  InvalidInputError = Class.new(StandardError)

  # The number of dimensions the current schema column supports.
  DB_DIMENSIONS = 1536

  def configured?
    ENV["OPENAI_API_KEY"].present?
  end

  def model
    @model ||= ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")
  end

  def dimensions
    @dimensions ||= ENV.fetch("OPENAI_EMBEDDING_DIMENSIONS", DB_DIMENSIONS.to_s).to_i
  end

  def batch_size
    @batch_size ||= ENV.fetch("OPENAI_EMBEDDING_BATCH_SIZE", "100").to_i
  end

  # Embeds an array of plain-text strings and returns an array of float vectors
  # in the same order. Raises one of the error classes above on failure.
  def embed_texts(texts)
    raise ConfigurationError,
      "OPENAI_API_KEY is not configured" unless configured?

    validate_dimensions!

    texts = Array(texts)
    return [] if texts.empty?

    preprocessed = texts.map { |t| preprocess(t) }
    blank_indices = preprocessed.each_index.select { |i| preprocessed[i].blank? }
    unless blank_indices.empty?
      raise InvalidInputError,
        "Texts at indices #{blank_indices.join(', ')} are blank after preprocessing"
    end

    results = []
    preprocessed.each_slice(batch_size) do |batch|
      results.concat(embed_batch(batch))
    end
    results
  end

  private

  def client
    @client ||= OpenAI::Client.new(
      access_token:    ENV.fetch("OPENAI_API_KEY"),
      request_timeout: 30
    )
  end

  def validate_dimensions!
    if dimensions != DB_DIMENSIONS
      raise ConfigurationError,
        "OPENAI_EMBEDDING_DIMENSIONS=#{dimensions} does not match the database " \
        "vector column width (#{DB_DIMENSIONS}). " \
        "Run a migration to change the column before using a different dimension."
    end
  end

  def embed_batch(texts)
    params = { model: model, input: texts }
    # The `dimensions` parameter is only supported by text-embedding-3-* models.
    params[:dimensions] = dimensions if third_gen_model?

    response = client.embeddings(parameters: params)

    data = response["data"]

    if data.nil? || data.empty?
      raise ValidationError,
        "Empty response from OpenAI embeddings API (model=#{model})"
    end

    if data.size != texts.size
      raise ValidationError,
        "OpenAI returned #{data.size} embeddings but #{texts.size} were requested"
    end

    # Sort by index to guarantee input order is preserved.
    vectors = data.sort_by { |d| d["index"] }.map { |d| d["embedding"] }

    vectors.each_with_index do |vec, i|
      if vec.size != dimensions
        raise ValidationError,
          "Embedding at position #{i} has #{vec.size} dimensions, expected #{dimensions}"
      end
    end

    vectors
  rescue Faraday::Error => e
    handle_faraday_error(e)
  rescue OpenAI::Error => e
    handle_openai_error(e)
  end

  def handle_faraday_error(error)
    handle_provider_error(
      status: error.response_status,
      body: error.response_body
    )
  end

  def handle_openai_error(error)
    response = error.respond_to?(:response) ? error.response : nil
    handle_provider_error(
      status: response&.dig(:status) || response&.dig("status"),
      body: response&.dig(:body) || response&.dig("body")
    )
  end

  def handle_provider_error(status:, body:)
    case status
    when 401, 403, 404
      raise ConfigurationError,
        "OpenAI embedding configuration was rejected (HTTP #{status})"
    when 400, 422
      raise InvalidInputError,
        "OpenAI rejected the embedding input (HTTP #{status})"
    when 429
      if quota_exhausted?(body)
        raise QuotaError,
          "OpenAI embedding quota is unavailable (HTTP 429)"
      end

      raise RateLimitError,
        "OpenAI embedding rate limit exceeded (HTTP 429)"
    when 408, 409, 500, 502, 503, 504
      raise ServiceError,
        "OpenAI embedding service is temporarily unavailable (HTTP #{status})"
    else
      raise ServiceError,
        "OpenAI embedding request failed (HTTP #{status || 'unknown'})"
    end
  end

  def quota_exhausted?(body)
    payload = body.is_a?(String) ? JSON.parse(body) : body
    return false unless payload.is_a?(Hash)

    details = payload["error"] || payload[:error] || payload
    return false unless details.is_a?(Hash)

    code = details["code"] || details[:code]
    type = details["type"] || details[:type]
    [ code, type ].compact.map(&:to_s).any? do |value|
      %w[insufficient_quota billing_hard_limit_reached].include?(value)
    end
  rescue JSON::ParserError
    false
  end

  # Normalises text before sending to OpenAI:
  # - Ensures valid UTF-8
  # - Collapses excessive whitespace (preserves single newlines for structure)
  # - Strips leading/trailing whitespace
  def preprocess(text)
    text.to_s
        .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        .gsub(/[[:space:]]+/, " ")
        .strip
  end

  def third_gen_model?
    model.start_with?("text-embedding-3-")
  end
end
