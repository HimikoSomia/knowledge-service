# Embedding::EmbeddingService — stub implementation
#
# Interface:
#   service = Embedding::EmbeddingService.new
#   service.embed(document)
#
# Expected behavior when implemented:
#   - Loads document.document_chunks (ordered by chunk_index)
#   - Calls the configured embedding provider for each chunk's content
#   - Updates DocumentChunk#embedding (vector, 1536 dims for OpenAI ada-002 /
#     text-embedding-3-small) and DocumentChunk#embedding_model
#   - Calls document.update_columns(embedded_at: Time.current, status: "embedded")
#     on completion
#
# To implement: pick an embedding provider, configure credentials via Rails
# credentials or ENV, and replace #embed below. The DocumentChunk#embedding
# column is already typed as vector(1536), matching OpenAI's small embedding models.
#
class Embedding::EmbeddingService
  def embed(_document)
    raise NotImplementedError,
      "Embedding::EmbeddingService#embed is not yet implemented. " \
      "Configure an embedding provider and implement this method."
  end
end
