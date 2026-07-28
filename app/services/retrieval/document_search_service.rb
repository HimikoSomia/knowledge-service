# Semantic search service using pgvector cosine similarity.
#
# Usage:
#   service = Retrieval::DocumentSearchService.new(current_user)
#   results = service.search("What is the quarterly revenue?", limit: 5)
#   results.each { |chunk| puts chunk.content; puts chunk.neighbor_distance }
#
# Authorization is applied at the SQL level — only chunks from the user's own
# documents are ever considered.
#
class Retrieval::DocumentSearchService
  NotConfiguredError = Class.new(StandardError)
  EmptyQueryError    = Class.new(ArgumentError)

  DEFAULT_LIMIT = 10

  def initialize(user)
    @user = user
  end

  # Generates a query embedding and returns the most semantically similar
  # DocumentChunk records the user is authorized to access.
  #
  # @param query       [String]  the user's natural-language query
  # @param limit       [Integer] maximum number of results (default: 10)
  # @param workspace_id [Integer, nil] restrict to a specific workspace
  # @return [ActiveRecord::Relation] chunks ordered by cosine distance (nearest first)
  def search(query, limit: DEFAULT_LIMIT, workspace_id: nil)
    raise EmptyQueryError, "Query cannot be blank" if query.to_s.strip.blank?

    service = embedding_service
    raise NotConfiguredError, "Embedding service is not configured (OPENAI_API_KEY missing)" unless service.configured?

    query_vector = service.embed_texts([ query.strip ]).first

    authorized_chunk_scope(workspace_id)
      .nearest_neighbors(:embedding, query_vector, distance: "cosine")
      .limit(limit)
  end

  private

  def embedding_service
    Embedding::OpenAiEmbeddingService.new
  end

  # Returns a DocumentChunk relation scoped to the current user's accessible
  # documents. Authorization and readiness checks live in SQL — no post-filter.
  def authorized_chunk_scope(workspace_id)
    scope = DocumentChunk
      .joins(:document)
      .where(
        documents:       { user_id: @user.id, status: "processed" },
        document_chunks: { embedding_model: current_model }
      )
      .where.not(document_chunks: { embedding: nil })

    if workspace_id.present?
      scope = scope
        .joins("INNER JOIN document_workspaces " \
               "ON document_workspaces.document_id = documents.id")
        .where(document_workspaces: { workspace_id: workspace_id })
    end

    scope
  end

  def current_model
    ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")
  end
end
