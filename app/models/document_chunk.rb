class DocumentChunk < ApplicationRecord
  belongs_to :document

  # Enables .nearest_neighbors(:embedding, vector, distance: "cosine") scope
  # provided by the neighbor gem (pgvector).
  has_neighbors :embedding

  validates :content, presence: true
  validates :chunk_index, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :source_key, uniqueness: { scope: :document_id }, allow_nil: true
end
