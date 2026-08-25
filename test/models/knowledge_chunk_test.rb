require "test_helper"

class KnowledgeChunkTest < ActiveSupport::TestCase
  test "requires unique non-negative chunk indexes within one source" do
    source = knowledge_sources(:note_one)
    duplicate = source.knowledge_chunks.new(
      chunk_index: 0,
      content: "Duplicate",
      content_checksum: "duplicate"
    )

    assert_not duplicate.valid?
    assert duplicate.errors[:chunk_index].any?

    duplicate.chunk_index = -1
    assert_not duplicate.valid?
  end
end
