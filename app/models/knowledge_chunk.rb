class KnowledgeChunk < ApplicationRecord
  belongs_to :knowledge_source

  has_neighbors :embedding

  validates :content, presence: true
  validates :content_checksum, presence: true
  validates :chunk_index, presence: true,
                          numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                          uniqueness: { scope: :knowledge_source_id }
end
