require "test_helper"

class Chunking::TextSplitterTest < ActiveSupport::TestCase
  test "returns no chunks for blank content" do
    assert_empty Chunking::TextSplitter.new.split("  ")
  end

  test "keeps short content in one chunk" do
    assert_equal [ "Short note." ], Chunking::TextSplitter.new.split("Short note.")
  end

  test "splits long content without exceeding the configured size" do
    parts = Chunking::TextSplitter.new(max_chars: 20).split("alpha beta gamma delta epsilon zeta")

    assert_operator parts.size, :>, 1
    assert parts.all? { |part| part.length <= 20 }
  end

  test "hard-splits a single oversized word" do
    parts = Chunking::TextSplitter.new(max_chars: 5).split("abcdefghijk")

    assert_equal %w[abcde fghij k], parts
  end
end
