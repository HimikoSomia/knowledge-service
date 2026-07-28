class AddEmbeddingFields < ActiveRecord::Migration[8.1]
  def change
    # Track the embedding pipeline stage on documents, mirroring enrichment_status.
    add_column :documents, :embedding_status, :string, null: false, default: "not_started"

    # Short SHA-256 digest per chunk — used by EmbedDocumentJob to detect when
    # content has changed and re-embedding is required.
    add_column :document_chunks, :content_checksum, :string

    # Speeds up "find chunks needing embedding for this model" queries.
    add_index :document_chunks, [ :document_id, :embedding_model ],
              name: "index_document_chunks_on_document_id_and_model"

    # ── Vector index note ────────────────────────────────────────────────────
    # For the current dataset size (< ~100 K chunks), PostgreSQL performs an
    # exact linear scan which is accurate and requires no special index.
    #
    # Once the chunk count exceeds ~100 K rows, add an HNSW index:
    #
    #   execute <<~SQL
    #     CREATE INDEX CONCURRENTLY document_chunks_embedding_hnsw
    #     ON document_chunks
    #     USING hnsw (embedding vector_cosine_ops)
    #     WITH (m = 16, ef_construction = 64);
    #   SQL
    #
    # The operator class must match the distance used in retrieval:
    #   vector_cosine_ops  → cosine distance  (<=>)
    #   vector_l2_ops      → Euclidean        (<->)
    #   vector_ip_ops      → inner product    (<#>)
    # ─────────────────────────────────────────────────────────────────────────
  end
end
