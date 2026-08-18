require "test_helper"

class Embedding::OpenAiEmbeddingServiceTest < ActiveSupport::TestCase
  DB_DIMS = Embedding::OpenAiEmbeddingService::DB_DIMENSIONS  # 1536

  setup do
    @service = Embedding::OpenAiEmbeddingService.new
    @original_client_new = OpenAI::Client.method(:new)
    ENV["OPENAI_API_KEY"] = "test-key"
  end

  teardown do
    ENV.delete("OPENAI_API_KEY")
    ENV.delete("OPENAI_EMBEDDING_MODEL")
    ENV.delete("OPENAI_EMBEDDING_DIMENSIONS")
    ENV.delete("OPENAI_EMBEDDING_BATCH_SIZE")
    if OpenAI::Client.singleton_class.method_defined?(:new, false)
      OpenAI::Client.singleton_class.remove_method(:new)
    end
    @service = Embedding::OpenAiEmbeddingService.new  # reset memoized state
  end

  # ── configuration ──────────────────────────────────────────────────────────

  test "configured? returns true when OPENAI_API_KEY is present" do
    assert @service.configured?
  end

  test "configured? returns false when OPENAI_API_KEY is absent" do
    ENV.delete("OPENAI_API_KEY")
    assert_not @service.configured?
  end

  test "model falls back to text-embedding-3-small by default" do
    assert_equal "text-embedding-3-small", @service.model
  end

  test "model reads OPENAI_EMBEDDING_MODEL" do
    ENV["OPENAI_EMBEDDING_MODEL"] = "text-embedding-ada-002"
    svc = Embedding::OpenAiEmbeddingService.new
    assert_equal "text-embedding-ada-002", svc.model
  end

  test "dimensions falls back to 1536 by default" do
    assert_equal 1536, @service.dimensions
  end

  test "raises ConfigurationError when dimensions do not match DB column" do
    ENV["OPENAI_EMBEDDING_DIMENSIONS"] = "3072"
    svc = Embedding::OpenAiEmbeddingService.new
    stub_client([])
    err = assert_raises(Embedding::OpenAiEmbeddingService::ConfigurationError) do
      svc.embed_texts([ "hello" ])
    end
    assert_match "3072", err.message
    assert_match "1536", err.message
  end

  test "raises ConfigurationError when API key is missing" do
    ENV.delete("OPENAI_API_KEY")
    assert_raises(Embedding::OpenAiEmbeddingService::ConfigurationError) do
      @service.embed_texts([ "hello" ])
    end
  end

  # ── successful embedding ───────────────────────────────────────────────────

  test "returns a vector for a single text" do
    stub_client([ fake_vector ])
    result = @service.embed_texts([ "hello world" ])
    assert_equal 1, result.size
    assert_equal DB_DIMS, result.first.size
  end

  test "returns vectors in input order for multiple texts" do
    v1 = fake_vector(0.1)
    v2 = fake_vector(0.2)
    v3 = fake_vector(0.3)
    # API returns them in reverse order to verify reordering
    stub_client([ v3, v2, v1 ], reverse_indices: true)
    result = @service.embed_texts([ "a", "b", "c" ])
    assert_equal [ v1, v2, v3 ], result
  end

  test "returns empty array for empty input" do
    result = @service.embed_texts([])
    assert_equal [], result
  end

  test "batches large inputs according to batch_size" do
    ENV["OPENAI_EMBEDDING_BATCH_SIZE"] = "2"
    svc = Embedding::OpenAiEmbeddingService.new
    call_count = 0
    stub_client_counting(call_count_ref: ->(n) { call_count = n }, responses: [
      [ fake_vector, fake_vector ],
      [ fake_vector ]
    ])
    result = svc.embed_texts([ "a", "b", "c" ])
    assert_equal 3, result.size
    assert_equal 2, call_count
  end

  # ── error handling ─────────────────────────────────────────────────────────

  test "raises InvalidInputError for blank text" do
    assert_raises(Embedding::OpenAiEmbeddingService::InvalidInputError) do
      @service.embed_texts([ "   " ])
    end
  end

  test "raises ValidationError when API returns empty data" do
    stub_client_with_response({ "data" => [], "usage" => {} })
    assert_raises(Embedding::OpenAiEmbeddingService::ValidationError) do
      @service.embed_texts([ "hello" ])
    end
  end

  test "raises ValidationError when returned count does not match input" do
    # Input has 2 texts, response has 1 embedding
    stub_client_with_response({ "data" => [ { "index" => 0, "embedding" => fake_vector } ], "usage" => {} })
    assert_raises(Embedding::OpenAiEmbeddingService::ValidationError) do
      @service.embed_texts([ "text a", "text b" ])
    end
  end

  test "raises ValidationError when vector dimension is wrong" do
    wrong_dim_vector = Array.new(512, 0.1)
    stub_client([ wrong_dim_vector ])
    assert_raises(Embedding::OpenAiEmbeddingService::ValidationError) do
      @service.embed_texts([ "hello" ])
    end
  end

  test "raises RateLimitError on HTTP 429" do
    stub_client_with_openai_error(status: 429, message: "rate limited")
    assert_raises(Embedding::OpenAiEmbeddingService::RateLimitError) do
      @service.embed_texts([ "hello" ])
    end
  end

  test "raises ConfigurationError on HTTP 401" do
    stub_client_with_openai_error(status: 401, message: "unauthorized")
    assert_raises(Embedding::OpenAiEmbeddingService::ConfigurationError) do
      @service.embed_texts([ "hello" ])
    end
  end

  test "raises ServiceError on HTTP 500" do
    stub_client_with_openai_error(status: 500, message: "internal error")
    assert_raises(Embedding::OpenAiEmbeddingService::ServiceError) do
      @service.embed_texts([ "hello" ])
    end
  end

  test "raises ServiceError on network timeout" do
    stub_client_with_network_error(Faraday::TimeoutError)
    assert_raises(Embedding::OpenAiEmbeddingService::ServiceError) do
      @service.embed_texts([ "hello" ])
    end
  end

  private

  def fake_vector(seed = 0.1)
    Array.new(DB_DIMS, seed)
  end

  # Stubs OpenAI::Client.new to return a fake client whose #embeddings method
  # returns a canned response. `vectors` is an Array of float arrays.
  def stub_client(vectors, reverse_indices: false)
    response = build_response(vectors, reverse_indices: reverse_indices)
    stub_client_with_response(response)
  end

  def stub_client_with_response(response)
    fake = Object.new
    fake.define_singleton_method(:embeddings) { |**_| response }
    OpenAI::Client.define_singleton_method(:new) { |**_| fake }
  end

  def stub_client_counting(call_count_ref:, responses:)
    call = 0
    fake = Object.new
    fake.define_singleton_method(:embeddings) do |**_|
      r = responses[call] || responses.last
      call += 1
      call_count_ref.call(call)
      # Build inline — no method lookup on test instance needed.
      data = r.each_with_index.map { |vec, i| { "index" => i, "embedding" => vec } }
      { "data" => data, "usage" => {} }
    end
    OpenAI::Client.define_singleton_method(:new) { |**_| fake }
  end

  def build_response(vectors, reverse_indices: false)
    data = vectors.each_with_index.map do |vec, i|
      { "index" => reverse_indices ? (vectors.size - 1 - i) : i, "embedding" => vec }
    end
    { "data" => data, "usage" => { "total_tokens" => vectors.size * 10 } }
  end

  def self.build_response_static(vectors)
    data = vectors.each_with_index.map { |v, i| { "index" => i, "embedding" => v } }
    { "data" => data, "usage" => {} }
  end

  def stub_client_with_openai_error(status:, message:)
    error = OpenAI::Error.new(message)
    error.define_singleton_method(:response) { { status: status } }
    fake = Object.new
    fake.define_singleton_method(:embeddings) { |**_| raise error }
    OpenAI::Client.define_singleton_method(:new) { |**_| fake }
  end

  def stub_client_with_network_error(error_class)
    fake = Object.new
    fake.define_singleton_method(:embeddings) { |**_| raise error_class.new("timeout") }
    OpenAI::Client.define_singleton_method(:new) { |**_| fake }
  end

  def build_response_static(vectors)
    self.class.build_response_static(vectors)
  end
end
