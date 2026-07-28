# Abstract interface for embedding services.
#
# Error hierarchy — defined here so background jobs can reference them via
# discard_on / retry_on without importing a concrete provider implementation.
#
# Usage (concrete subclass):
#   service = Embedding::OpenAiEmbeddingService.new
#   vectors = service.embed_texts(["chunk content ..."])  # => [[0.12, ...], ...]
#
class Embedding::EmbeddingService
  # Raised for permanent configuration problems (missing key, wrong dimensions).
  # Jobs should discard — retrying will not fix the issue.
  ConfigurationError = Class.new(StandardError)

  # Raised when the provider enforces a rate limit (HTTP 429).
  # Jobs should retry with backoff.
  RateLimitError = Class.new(StandardError)

  # Raised for transient provider / network failures (timeouts, 5xx).
  # Jobs should retry with backoff.
  ServiceError = Class.new(StandardError)

  # Raised when the API response fails structural validation
  # (wrong count, wrong dimensions, empty body).
  ValidationError = Class.new(StandardError)

  # Raised for permanently invalid input (token limit exceeded, encoding error).
  # Jobs should discard the affected chunk rather than retrying forever.
  InvalidInputError = Class.new(StandardError)

  # ── Interface ──────────────────────────────────────────────────────────────

  # Returns true when all required credentials and configuration are present.
  def configured?
    false
  end

  # The embedding model identifier, e.g. "text-embedding-3-small".
  def model
    raise NotImplementedError, "#{self.class}#model is not implemented"
  end

  # The number of dimensions the model produces. Must match the database column.
  def dimensions
    raise NotImplementedError, "#{self.class}#dimensions is not implemented"
  end

  # Maximum number of texts to send in a single API request.
  def batch_size
    raise NotImplementedError, "#{self.class}#batch_size is not implemented"
  end

  # Embeds an array of plain-text strings.
  # Returns an array of float arrays in the same order as the input.
  # Raises one of the error subclasses above on failure.
  def embed_texts(_texts)
    raise NotImplementedError, "#{self.class}#embed_texts is not implemented"
  end
end

