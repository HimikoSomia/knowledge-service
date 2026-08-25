class Retrieval::WorkspaceKnowledgeSearchService
  NotConfiguredError = Class.new(StandardError)
  EmptyQueryError = Class.new(ArgumentError)

  Candidate = Data.define(
    :chunk_id,
    :content,
    :source_type,
    :source_id,
    :source_title,
    :source_locator,
    :metadata,
    :neighbor_distance
  )

  def initialize(user, embedding_service: Embedding::OpenAiEmbeddingService.new)
    @user = user
    @embedding_service = embedding_service
  end

  def search(query, workspace_id:, limit:)
    query = query.to_s.strip
    raise EmptyQueryError, "Query cannot be blank" if query.blank?
    raise ActiveRecord::RecordNotFound unless user.workspaces.exists?(workspace_id)
    raise NotConfiguredError, "Embedding service is not configured" unless embedding_service.configured?

    vector = embedding_service.embed_texts([ query ]).first
    candidates = document_candidates(workspace_id, vector, limit) +
                 knowledge_candidates(workspace_id, vector, limit)
    candidates.sort_by(&:neighbor_distance).first(limit)
  end

  private

  attr_reader :user, :embedding_service

  def document_candidates(workspace_id, vector, limit)
    DocumentChunk
      .joins(document: :document_workspaces)
      .where(
        documents: { user_id: user.id, status: "ready" },
        document_workspaces: { workspace_id: workspace_id },
        document_chunks: { embedding_model: embedding_service.model }
      )
      .where.not(document_chunks: { embedding: nil })
      .nearest_neighbors(:embedding, vector, distance: "cosine")
      .includes(:document)
      .limit(limit)
      .map { |chunk| document_candidate(chunk) }
  end

  def knowledge_candidates(workspace_id, vector, limit)
    KnowledgeChunk
      .joins(:knowledge_source)
      .where(
        knowledge_sources: { user_id: user.id, workspace_id: workspace_id, status: "ready" },
        knowledge_chunks: { embedding_model: embedding_service.model }
      )
      .where.not(knowledge_chunks: { embedding: nil })
      .nearest_neighbors(:embedding, vector, distance: "cosine")
      .includes(:knowledge_source)
      .limit(limit)
      .map { |chunk| knowledge_candidate(chunk) }
  end

  def document_candidate(chunk)
    Candidate.new(
      chunk_id: chunk.id,
      content: chunk.content,
      source_type: "document",
      source_id: chunk.document_id,
      source_title: chunk.document.title,
      source_locator: document_locator(chunk),
      metadata: chunk.metadata,
      neighbor_distance: chunk.neighbor_distance.to_f
    )
  end

  def knowledge_candidate(chunk)
    source = chunk.knowledge_source
    Candidate.new(
      chunk_id: chunk.id,
      content: chunk.content,
      source_type: source.source_type,
      source_id: source.id,
      source_title: source.title,
      source_locator: chunk.metadata["locator"].presence || "Section #{chunk.chunk_index + 1}",
      metadata: chunk.metadata,
      neighbor_distance: chunk.neighbor_distance.to_f
    )
  end

  def document_locator(chunk)
    return "Page #{chunk.page_number}" if chunk.page_number.present?

    chunk.metadata.dig("heading", "content").presence || "Chunk #{chunk.chunk_index + 1}"
  end
end
