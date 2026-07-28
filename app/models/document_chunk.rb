class DocumentChunk < ApplicationRecord
  belongs_to :document

  validates :content, presence: true
  validates :chunk_index, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
