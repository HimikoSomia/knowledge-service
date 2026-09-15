require "minitest/autorun"
require_relative "./support/dataset"

class DatasetTest < Minitest::Test
  def test_valid_dataset_data_is_valid
    dataset = Dataset.new(valid_dataset_data)

    assert dataset.valid?, dataset.errors.join("\n")
  end

  def test_v1_dataset_is_valid
    dataset = Dataset.load(
      File.expand_path("./data/retrieval_v1.yml", __dir__)
    )

    assert dataset.valid?, dataset.errors.join("\n")
  end

  def test_long_context_case_exceeds_budget_without_exceeding_source_cap
    dataset = Dataset.load(
      File.expand_path("./data/retrieval_v1.yml", __dir__)
    )
    question = dataset.question("long_context_budget")
    chunks = question.fetch("expected_chunk_keys").map { |key| dataset.chunk(key) }
    contents = chunks.map { |chunk| dataset.expanded_chunk_content(chunk).strip }
    budget = dataset.defaults.fetch("max_context_chars")

    assert_equal 6, chunks.size
    assert_equal [ 3, 3 ], chunks.map { |chunk| chunk.fetch("source_key") }.tally.values.sort
    assert_operator contents.sum(&:length), :>, budget
    assert_operator contents.map(&:length).sort.reverse.first(5).sum, :<=, budget
  end

  def test_expands_repeated_chunk_content
    dataset = Dataset.new(valid_dataset_data)
    chunk = dataset.chunks.first.merge("content" => "abc", "content_repeat" => 3)

    assert_equal "abcabcabc", dataset.expanded_chunk_content(chunk)
  end

  def test_rejects_non_hash_dataset_root
    dataset = Dataset.new(nil)

    refute dataset.valid?
    assert_includes dataset.errors, "Dataset root must be a hash"
  end

  def test_rejects_non_array_collection
    data = valid_dataset_data
    data["users"] = "invalid"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Users must be an array"
  end

  def test_rejects_non_hash_collection_entry
    data = valid_dataset_data
    data["users"] << "invalid"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Users entry at index 2 must be a hash"
  end

  def test_rejects_unsupported_version
    data = valid_dataset_data
    data["version"] = 999

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Unsupported dataset version: 999"
  end

  def test_rejects_missing_version
    data = valid_dataset_data
    data.delete("version")

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Version must be specified"
  end

  def test_rejects_non_integer_version
    data = valid_dataset_data
    data["version"] = "invalid"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Version must be an integer"
  end

  def test_rejects_non_hash_defaults
    data = valid_dataset_data
    data["defaults"] = "invalid"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Defaults must be a hash"
  end

  def test_rejects_invalid_defaults
    data = valid_dataset_data
    data["defaults"]["top_k"] = -1

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Default top_k must be greater than 0"

    data["defaults"]["distance_threshold"] = -1
    dataset = Dataset.new(data)
    refute dataset.valid?
    assert_includes dataset.errors, "Default distance_threshold must be greater than 0"

    data["defaults"]["top_k"] = "invalid"
    dataset = Dataset.new(data)
    refute dataset.valid?
    assert_includes dataset.errors, "Default top_k must be an integer"

    data["defaults"]["distance_threshold"] = "invalid"
    dataset = Dataset.new(data)
    refute dataset.valid?
    assert_includes dataset.errors, "Default distance_threshold must be a number"
  end

  def test_rejects_invalid_max_context_chars
    data = valid_dataset_data
    data["defaults"]["max_context_chars"] = 0

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Default max_context_chars must be greater than 0"

    data["defaults"]["max_context_chars"] = "invalid"
    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Default max_context_chars must be an integer"
  end

  def test_rejects_malformed_distance_boundary_expectation
    data = valid_dataset_data
    data["questions"].first["retrieval_expectation"] = {
      "type" => "distance_boundary",
      "target_chunk_key" => "chunk_1",
      "comparison" => "invalid_comparison",
      "threshold" => "not_a_number",
      "deterministic_distance" => "not_a_number"
    }

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 has invalid distance comparison \"invalid_comparison\""
    assert_includes dataset.errors, "Question question_1 requires a positive numeric distance threshold"
    assert_includes dataset.errors,
      "Question question_1 requires a finite deterministic cosine distance between 0 and 2"
  end

  def test_rejects_non_hash_retrieval_expectation
    data = valid_dataset_data
    data["questions"].first["retrieval_expectation"] = 123

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 has invalid retrieval expectation format"
  end

  def test_rejects_unknown_retrieval_expectation_type
    data = valid_dataset_data
    data["questions"].first["retrieval_expectation"] = { "type" => "unknown" }

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, 'Question question_1 has invalid retrieval expectation type "unknown"'
  end

  def test_rejects_distance_boundary_that_conflicts_with_abstention
    data = valid_dataset_data
    data["questions"].first["retrieval_expectation"] = {
      "type" => "distance_boundary",
      "target_chunk_key" => "chunk_1",
      "comparison" => "less_than_or_equal",
      "threshold" => 0.55,
      "deterministic_distance" => 0.56
    }

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 distance expectation conflicts with expect_abstention"
  end

  def test_rejects_deterministic_cosine_distance_above_two
    data = valid_dataset_data
    expectation = data["questions"].last.fetch("retrieval_expectation")
    expectation["threshold"] = 3.0
    expectation["deterministic_distance"] = 2.01

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors,
      "Question question_2 requires a finite deterministic cosine distance between 0 and 2"
  end

  def test_rejects_non_finite_deterministic_cosine_distance
    data = valid_dataset_data
    expectation = data["questions"].last.fetch("retrieval_expectation")
    expectation["threshold"] = Float::INFINITY
    expectation["deterministic_distance"] = Float::INFINITY

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors,
      "Question question_2 requires a finite deterministic cosine distance between 0 and 2"
  end

  def test_rejects_distance_expectation_without_target_chunk
    data = valid_dataset_data
    data["questions"].last["retrieval_expectation"].delete("target_chunk_key")

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_2 retrieval expectation requires a target chunk key"
  end

  def test_rejects_distance_expectation_with_missing_target_chunk
    data = valid_dataset_data
    data["questions"].last["retrieval_expectation"]["target_chunk_key"] = "missing_chunk"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_2 references missing retrieval target chunk missing_chunk"
  end

  def test_rejects_distance_expectation_with_target_outside_question_scope
    data = valid_dataset_data
    data["questions"].last["retrieval_expectation"]["target_chunk_key"] = "chunk_1"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors,
      "Question question_2 retrieval target chunk chunk_1 belongs to a different user"
    assert_includes dataset.errors,
      "Question question_2 retrieval target chunk chunk_1 belongs to a different workspace"
  end

  def test_rejects_successful_retrieval_target_that_is_not_expected
    data = valid_dataset_data
    extra_chunk = data["chunks"].first.merge(
      "key" => "chunk_3",
      "semantic_label" => "other_policy"
    )
    data["chunks"] << extra_chunk
    data["questions"].first["retrieval_expectation"] = valid_provider_threshold_expectation.merge(
      "target_chunk_key" => "chunk_3"
    )

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors,
      "Question question_1 retrieval target chunk must be expected when retrieval should succeed"
  end

  def test_accepts_valid_provider_threshold_expectation
    data = valid_dataset_data
    data["questions"].first["retrieval_expectation"] = valid_provider_threshold_expectation

    dataset = Dataset.new(data)

    assert dataset.valid?, dataset.errors.join("\n")
  end

  def test_rejects_malformed_provider_threshold_expectation
    data = valid_dataset_data
    expectation = valid_provider_threshold_expectation
    expectation["provider"]["expected_behavior"] = "unknown"
    expectation["provider"]["regression_note"] = " "
    data["questions"].first["retrieval_expectation"] = expectation

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, 'Question question_1 has invalid provider expected behavior "unknown"'
    assert_includes dataset.errors, "Question question_1 requires a provider regression note"
  end

  def test_rejects_blank_chunk_key
    data = valid_dataset_data
    data["chunks"].first["key"] = " "

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Chunk key cannot be blank"
  end

  def test_rejects_blank_chunk_content
    data = valid_dataset_data
    data["chunks"].first["content"] = ""

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Chunk chunk_1 content cannot be blank"
  end

  def test_rejects_blank_chunk_semantic_label
    data = valid_dataset_data
    data["chunks"].first["semantic_label"] = nil

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Chunk chunk_1 semantic_label cannot be blank"
  end

  def test_rejects_invalid_chunk_content_repeat
    data = valid_dataset_data
    data["chunks"].first["content_repeat"] = 0

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Chunk chunk_1 content_repeat must be a positive integer"

    data["chunks"].first["content_repeat"] = "invalid"
    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Chunk chunk_1 content_repeat must be a positive integer"
  end

  def test_rejects_duplicate_chunk_keys
    data = valid_dataset_data
    data["chunks"] << data["chunks"].first.dup

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Duplicate chunk key: #{data["chunks"].first["key"]}"
  end

  def test_rejects_missing_source_reference
    data = valid_dataset_data
    data["chunks"].first["source_key"] = "missing_source"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Chunk chunk_1 references missing source missing_source"
  end

  def test_rejects_missing_workspace_reference
    data = valid_dataset_data
    data["sources"].first["workspace_keys"] = [ "missing_workspace" ]

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Source source_1 references missing workspace missing_workspace"
  end

  def test_rejects_blank_question_key
    data = valid_dataset_data
    data["questions"].first["key"] = " "

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question key cannot be blank"
  end

  def test_rejects_scalar_question_expected_chunk_keys
    data = valid_dataset_data
    data["questions"].first["expected_chunk_keys"] = "not_an_array"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 expected_chunk_keys must be an array"
  end

  def test_rejects_scalar_question_forbidden_chunk_keys
    data = valid_dataset_data
    data["questions"].first["forbidden_chunk_keys"] = "not_an_array"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 forbidden_chunk_keys must be an array"
  end

  def test_rejects_answerable_case_without_expected_chunks
    data = valid_dataset_data
    data["questions"].first["expected_chunk_keys"] = []
    data["questions"].first["forbidden_chunk_keys"] = []
    data["questions"].first["expect_abstention"] = false

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 does not expect abstention but has no expected chunks"
  end

  def test_rejects_expected_forbidden_overlap
    data = valid_dataset_data
    data["questions"].first["forbidden_chunk_keys"] = [ "chunk_1" ]
    rejected_data = data["questions"].first

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question #{rejected_data["key"]} has #{rejected_data["forbidden_chunk_keys"].first} overlap between expected and forbidden chunks"
  end

  def test_rejects_duplicate_keys
    data = valid_dataset_data
    data["users"] << { "key" => "user_1", "name" => "Alice Duplicate" }

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Duplicate user key: user_1"
  end

  def test_rejects_missing_user_reference
    data = valid_dataset_data
    data["workspaces"].first["user_key"] = "missing_user"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Workspace workspace_1 references missing user missing_user"
  end

  def test_rejects_source_workspace_ownership_mismatch
    data = valid_dataset_data
    data["sources"].first["workspace_keys"] = [ "workspace_2" ]

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Source source_1 is assigned to workspace workspace_2 which belongs to a different user"
  end

  def test_rejects_question_workspace_ownership_mismatch
    data = valid_dataset_data
    data["questions"].first["workspace_key"] = "workspace_2"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 is assigned to workspace workspace_2 which belongs to a different user"
  end

  def test_rejects_expected_chunk_outside_question_scope
    data = valid_dataset_data
    data["questions"].first["expected_chunk_keys"] = [ "chunk_1" ]
    data["chunks"].first["source_key"] = "source_2"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 expects chunk chunk_1 which belongs to a different workspace"
  end

  def test_rejects_blank_question
    data = valid_dataset_data
    data["questions"].first["question"] = ""

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 has blank question text"
  end

  def test_rejects_invalid_source_type
    data = valid_dataset_data
    data["sources"].first["type"] = "invalid_type"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Source source_1 has invalid type #{data["sources"].first["type"].inspect}"
  end

  def test_rejects_invalid_expected_match
    data = valid_dataset_data
    data["questions"].first["expected_match"] = "invalid"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, 'Question question_1 has invalid expected_match "invalid"'
  end

  def test_rejects_non_boolean_expect_abstention
    data = valid_dataset_data
    data["questions"].first["expect_abstention"] = "false"

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 must define expect_abstention as true or false"
  end

  def test_rejects_source_without_workspace_assignment
    data = valid_dataset_data
    data["sources"].first["workspace_keys"] = []

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Source source_1 must have at least one workspace key"
  end

  def test_rejects_abstention_with_expected_chunks
    data = valid_dataset_data
    data["questions"].first["expect_abstention"] = true
    data["questions"].first["expected_chunk_keys"] = [ "chunk_1" ]

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 expects abstention but also defines expected chunks"
  end

  def test_rejects_expected_chunk_belonging_to_another_user
    data = valid_dataset_data
    data["questions"].last["expected_chunk_keys"] = [ "chunk_1" ]
    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_2 expects chunk chunk_1 which belongs to a different user"
  end

  def test_rejects_expected_chunk_belonging_to_another_workspace
    data = valid_dataset_data
    data["questions"].first["workspace_key"] = "workspace_3"
    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 expects chunk chunk_1 which belongs to a different workspace"
  end

  def test_rejects_question_referencing_missing_chunk
    data = valid_dataset_data
    data["questions"].first["expected_chunk_keys"] = [ "missing_chunk" ]

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 references missing chunk missing_chunk"
  end

  def test_rejects_question_referencing_missing_forbidden_chunk
    data = valid_dataset_data
    data["questions"].first["forbidden_chunk_keys"] = [ "missing_chunk" ]

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 references missing chunk missing_chunk"
  end

  def test_rejects_question_missing_retrieval_expectation_deterministic
    data = valid_dataset_data
    expectation = valid_provider_threshold_expectation
    expectation.delete("deterministic")
    data["questions"].first["retrieval_expectation"] = expectation

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 requires a deterministic provider expectation"
  end

  def test_rejects_question_missing_retrieval_expectation_provider
    data = valid_dataset_data
    expectation = valid_provider_threshold_expectation
    expectation.delete("provider")
    data["questions"].first["retrieval_expectation"] = expectation

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 requires a provider expectation"
  end

  def test_rejects_question_with_invalid_configured_distance_threshold
    data = valid_dataset_data
    expectation = valid_provider_threshold_expectation
    expectation["configured_distance_threshold"] = -0.1
    data["questions"].first["retrieval_expectation"] = expectation

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 requires a positive numeric configured distance threshold"
  end

  def test_rejects_question_with_deterministic_distance_conflicting_with_should_retrieve
    data = valid_dataset_data
    expectation = valid_provider_threshold_expectation
    expectation["deterministic"]["distance"] = 0.6
    data["questions"].first["retrieval_expectation"] = expectation

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors, "Question question_1 deterministic provider result conflicts with its configured threshold"
  end

  def test_rejects_provider_cosine_distance_above_two
    data = valid_dataset_data
    expectation = valid_provider_threshold_expectation
    expectation["configured_distance_threshold"] = 3.0
    expectation["deterministic"]["distance"] = 2.01
    data["questions"].first["retrieval_expectation"] = expectation

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors,
      "Question question_1 requires a finite deterministic provider cosine distance between 0 and 2"
  end

  def test_rejects_question_with_expect_abstention_conflicting_with_should_retrieve
    data = valid_dataset_data
    question = data["questions"].first

    question["expect_abstention"] = true
    question["expected_chunk_keys"] = []
    question["retrieval_expectation"] = valid_provider_threshold_expectation

    dataset = Dataset.new(data)

    refute dataset.valid?
    assert_includes dataset.errors,
      "Question question_1 deterministic provider result conflicts with expect_abstention"
  end

  private

  def valid_dataset_data
    {
      "version" => 1,
      "defaults" => {
        "top_k" => 5,
        "distance_threshold" => 0.55,
        "max_context_chars" => 16_000
      },
      "users" => [
        {
          "key" => "user_1",
          "name" => "Alice"
        },
        {
          "key" => "user_2",
          "name" => "Bob"
        }
      ],
      "workspaces" => [
        {
          "key" => "workspace_1",
          "user_key" => "user_1",
          "name" => "Workspace"
        },
        {
          "key" => "workspace_2",
          "user_key" => "user_2",
          "name" => "Another Workspace"
        },
        {
          "key" => "workspace_3",
          "user_key" => "user_1",
          "name" => "Third Workspace"
        }
      ],
      "sources" => [
        {
          "key" => "source_1",
          "type" => "document",
          "user_key" => "user_1",
          "workspace_keys" => [ "workspace_1" ],
          "title" => "Document"
        },
        {
          "key" => "source_2",
          "type" => "document",
          "user_key" => "user_2",
          "workspace_keys" => [ "workspace_2" ],
          "title" => "Another Document"
        }
      ],
      "chunks" => [
        {
          "key" => "chunk_1",
          "source_key" => "source_1",
          "semantic_label" => "refund_policy",
          "content" => "Refunds are available within thirty days."
        },
        {
          "key" => "chunk_2",
          "source_key" => "source_2",
          "semantic_label" => "shipping_policy",
          "content" => "Shipping takes 5-7 business days."
        }
      ],
      "questions" => [
        {
          "key" => "question_1",
          "user_key" => "user_1",
          "workspace_key" => "workspace_1",
          "question" => "What is the refund period?",
          "semantic_label" => "refund_policy",
          "expected_chunk_keys" => [ "chunk_1" ],
          "forbidden_chunk_keys" => [],
          "expect_abstention" => false,
          "expected_match" => "all"
        },
        {
          "key" => "question_2",
          "user_key" => "user_2",
          "workspace_key" => "workspace_2",
          "question" => "What is the shipping period?",
          "semantic_label" => "shipping_policy",
          "expected_chunk_keys" => [ "chunk_2" ],
          "forbidden_chunk_keys" => [],
          "expect_abstention" => false,
          "expected_match" => "all",
          "retrieval_expectation" => {
            "type" => "distance_boundary",
            "target_chunk_key" => "chunk_2",
            "comparison" => "less_than_or_equal",
            "threshold" => 0.5,
            "deterministic_distance" => 0.45
          }
        }
      ]
    }
  end

  def valid_provider_threshold_expectation
    {
      "type" => "provider_threshold_sensitive",
      "target_chunk_key" => "chunk_1",
      "configured_distance_threshold" => 0.55,
      "deterministic" => {
        "should_retrieve" => true,
        "distance" => 0.52
      },
      "provider" => {
        "expected_behavior" => "may_exceed_threshold",
        "regression_note" => "Provider embeddings may exceed the configured threshold."
      }
    }
  end
end
