# test/evaluation/support/dataset.rb

require "yaml"

class Dataset
  class ValidationError < StandardError; end

  ALLOWED_SOURCE_TYPES = %w[document note memo].freeze
  ALLOWED_EXPECTED_MATCHES = %w[any all].freeze
  ALLOWED_DISTANCE_COMPARISONS = %w[
    less_than_or_equal
  ].freeze
  ALLOWED_PROVIDER_EXPECTED_BEHAVIORS = %w[
    may_exceed_threshold
  ].freeze
  SUPPORTED_VERSION = 1

  attr_reader :version,
              :defaults,
              :users,
              :workspaces,
              :sources,
              :chunks,
              :questions,
              :errors

  def self.load(path)
    data = YAML.safe_load(
      File.read(path),
      aliases: false
    )

    new(data)
  end

  def initialize(data)
    @errors = []
    @structure_errors = []

    data = normalize_root(data)

    @version = data.fetch("version", nil)
    @defaults = data.fetch("defaults", {})
    @users = normalize_collection(data, "users", "Users")
    @workspaces = normalize_collection(data, "workspaces", "Workspaces")
    @sources = normalize_collection(data, "sources", "Sources")
    @chunks = normalize_collection(data, "chunks", "Chunks")
    @questions = normalize_collection(data, "questions", "Questions")
  end

  def valid?
    validate
    errors.empty?
  end

  def validate!
    validate

    return self if errors.empty?

    raise ValidationError, errors.join("\n")
  end

  def user(key)
    users_by_key[key]
  end

  def workspace(key)
    workspaces_by_key[key]
  end

  def source(key)
    sources_by_key[key]
  end

  def chunk(key)
    chunks_by_key[key]
  end

  def question(key)
    questions_by_key[key]
  end

  def expanded_chunk_content(chunk)
    repeat = chunk["content_repeat"]
    repeat = 1 unless repeat.is_a?(Integer) && repeat.positive?

    chunk["content"].to_s * repeat
  end

  private

  def validate
    errors.replace(@structure_errors)
    reset_indexes

    validate_version
    validate_defaults
    validate_unique_keys
    validate_empty_collections
    validate_users
    validate_workspaces
    validate_workspace_references
    validate_sources
    validate_source_references
    validate_chunk_references
    validate_blank_chunk_keys
    validate_blank_chunk_fields
    validate_blank_chunk_semantic_labels
    validate_chunk_content_repeats
    validate_questions

    self
  end

  def validate_version
    if version.nil?
      errors << "Version must be specified"
    elsif !version.is_a?(Integer)
      errors << "Version must be an integer"
    elsif version != SUPPORTED_VERSION
      errors << "Unsupported dataset version: #{version}"
    end
  end

  def validate_defaults
    unless defaults.is_a?(Hash)
      errors << "Defaults must be a hash"
      return
    end

    if defaults.key?("top_k")
      if !defaults["top_k"].is_a?(Integer)
        errors << "Default top_k must be an integer"
      elsif defaults["top_k"] <= 0
        errors << "Default top_k must be greater than 0"
      end
    end

    if defaults.key?("distance_threshold")
      if !defaults["distance_threshold"].is_a?(Numeric)
        errors << "Default distance_threshold must be a number"
      elsif defaults["distance_threshold"] <= 0
        errors << "Default distance_threshold must be greater than 0"
      end
    end

    if defaults.key?("max_context_chars")
      if !defaults["max_context_chars"].is_a?(Integer)
        errors << "Default max_context_chars must be an integer"
      elsif defaults["max_context_chars"] <= 0
        errors << "Default max_context_chars must be greater than 0"
      end
    end
  end

  def validate_unique_keys
    check_duplicate_keys(users, "key", "user")
    check_duplicate_keys(workspaces, "key", "workspace")
    check_duplicate_keys(sources, "key", "source")
    check_duplicate_keys(chunks, "key", "chunk")
    check_duplicate_keys(questions, "key", "question")
  end

  def validate_users
    users.each do |user|
      if user["key"].to_s.strip.empty?
        errors << "User key cannot be blank"
      end
    end
  end

  def validate_empty_collections
    if users.empty?
      errors << "At least one user must be defined"
    end

    if workspaces.empty?
      errors << "At least one workspace must be defined"
    end

    if sources.empty?
      errors << "At least one source must be defined"
    end

    if chunks.empty?
      errors << "At least one chunk must be defined"
    end

    if questions.empty?
      errors << "At least one question must be defined"
    end
  end

  def validate_workspaces
    workspaces.each do |workspace|
      if workspace["key"].to_s.strip.empty?
        errors << "Workspace key cannot be blank"
      end

      if workspace["name"].to_s.strip.empty?
        errors << "Workspace #{workspace["key"]} name cannot be blank"
      end
    end
  end

  def validate_workspace_references
    workspaces.each do |workspace|
      unless users_by_key.key?(workspace["user_key"])
        errors << "Workspace #{workspace["key"]} references missing user #{workspace["user_key"]}"
      end
    end
  end

  def validate_source_user_ownership_with_assigned_workspaces
    sources.each do |source|
      Array(source["workspace_keys"]).each do |workspace_key|
        workspace = workspaces_by_key[workspace_key]
        if workspace && workspace["user_key"] != source["user_key"]
          errors << "Source #{source["key"]} is assigned to workspace #{workspace_key} which belongs to a different user"
        end
      end
    end
  end

  def validate_sources
    sources.each do |source|
      if source["key"].to_s.strip.empty?
        errors << "Source key cannot be blank"
      end

      if source["title"].to_s.strip.empty?
        errors << "Source #{source["key"]} title cannot be blank"
      end

      if source["workspace_keys"].to_s.strip.empty?
        errors << "Source #{source["key"]} must be assigned to at least one workspace"
      end
    end
  end

  def validate_source_references
    validate_source_user_ownership_with_assigned_workspaces
    sources.each do |source|
      unless ALLOWED_SOURCE_TYPES.include?(source["type"])
        errors << "Source #{source["key"]} has invalid type #{source["type"].inspect}"
      end

      unless users_by_key.key?(source["user_key"])
        errors << "Source #{source["key"]} references missing user #{source["user_key"]}"
      end

      unless source["workspace_keys"].is_a?(Array) && !source["workspace_keys"].empty?
        errors << "Source #{source["key"]} must have at least one workspace key"
      end

      Array(source["workspace_keys"]).each do |workspace_key|
        unless workspaces_by_key.key?(workspace_key)
          errors << "Source #{source["key"]} references missing workspace #{workspace_key}"
        end
      end
    end
  end

  def validate_chunk_references
    chunks.each do |chunk|
      unless sources_by_key.key?(chunk["source_key"])
        errors << "Chunk #{chunk["key"]} references missing source #{chunk["source_key"]}"
      end
    end
  end

  def validate_blank_chunk_keys
    chunks.each do |chunk|
      if chunk["key"].to_s.strip.empty?
        errors << "Chunk key cannot be blank"
      end
    end
  end

  def validate_blank_chunk_fields
    chunks.each do |chunk|
      if chunk["content"].to_s.strip.empty?
        errors << "Chunk #{chunk["key"]} content cannot be blank"
      end
    end
  end

  def validate_blank_chunk_semantic_labels
    chunks.each do |chunk|
      if chunk["semantic_label"].to_s.strip.empty?
        errors << "Chunk #{chunk["key"]} semantic_label cannot be blank"
      end
    end
  end

  def validate_chunk_content_repeats
    chunks.each do |chunk|
      next unless chunk.key?("content_repeat")

      repeat = chunk["content_repeat"]
      unless repeat.is_a?(Integer) && repeat.positive?
        errors << "Chunk #{chunk["key"]} content_repeat must be a positive integer"
      end
    end
  end

  def validate_questions
    questions.each do |question|
      key = question["key"]

      validate_question_key(question, key)
      validate_question_semantic_label(question, key)
      validate_question_text(question, key)
      validate_question_scope(question, key)
      validate_question_expectations(question, key)
      validate_question_user_ownership_within_workspace(question, key)
      validate_question_sources(question, key)
      validate_expected_chunks_belong_to_question_scope(question, key)
      validate_distance_expectation(question, key)
    end
  end

  def validate_question_key(question, key)
    if key.to_s.strip.empty?
      errors << "Question key cannot be blank"
    end
  end

  def validate_question_semantic_label(question, key)
    if question["semantic_label"].to_s.strip.empty?
      errors << "Question #{key} semantic_label cannot be blank"
    end
  end

  def validate_question_text(question, key)
    if question["question"].to_s.strip.empty?
      errors << "Question #{key} has blank question text"
    end
  end

  def validate_question_scope(question, key)
    unless users_by_key.key?(question["user_key"])
      errors << "Question #{key} references missing user #{question["user_key"]}"
    end

    unless workspaces_by_key.key?(question["workspace_key"])
      errors << "Question #{key} references missing workspace #{question["workspace_key"]}"
    end
  end

  def validate_question_expectations(question, key)
    abstention = question["expect_abstention"]

    unless [ true, false ].include?(abstention)
      errors << "Question #{key} must define expect_abstention as true or false"
    end

    expected_match = question["expected_match"]

    if expected_match &&
        !ALLOWED_EXPECTED_MATCHES.include?(expected_match)
      errors << "Question #{key} has invalid expected_match #{expected_match.inspect}"
    end

    expected = Array(question["expected_chunk_keys"])

    if abstention == true && expected.any?
      errors << "Question #{key} expects abstention but also defines expected chunks"
    end

    if abstention == false && expected.empty?
      errors << "Question #{key} does not expect abstention but has no expected chunks"
    end
  end

  def validate_question_user_ownership_within_workspace(question, key)
    workspace = workspaces_by_key[question["workspace_key"]]
    if workspace && workspace["user_key"] != question["user_key"]
      errors << "Question #{key} is assigned to workspace #{question["workspace_key"]} which belongs to a different user"
    end
  end

  def validate_question_sources(question, key)
    unless question["expected_chunk_keys"].is_a?(Array)
      errors << "Question #{key} expected_chunk_keys must be an array"
      return
    end
    unless question["forbidden_chunk_keys"].is_a?(Array)
      errors << "Question #{key} forbidden_chunk_keys must be an array"
      return
    end

    expected = question["expected_chunk_keys"]
    forbidden = question["forbidden_chunk_keys"]

    (expected + forbidden).each do |source_key|
      unless chunks_by_key.key?(source_key)
        errors << "Question #{key} references missing chunk #{source_key}"
      end
    end

    overlap = expected & forbidden

    overlap.each do |source_key|
      errors << "Question #{key} has #{source_key} overlap between expected and forbidden chunks"
    end
  end

  def validate_distance_expectation(question, key)
    expectation = question["retrieval_expectation"]
    return unless expectation

    unless expectation.is_a?(Hash)
      errors << "Question #{key} has invalid retrieval expectation format"
      return
    end

    case expectation["type"]
    when "distance_boundary"
      validate_distance_boundary_expectation(question, key, expectation)
    when "provider_threshold_sensitive"
      validate_provider_threshold_expectation(question, key, expectation)
    else
      errors << "Question #{key} has invalid retrieval expectation type #{expectation["type"].inspect}"
    end
  end

  def validate_distance_boundary_expectation(question, key, expectation)
    target_valid = validate_retrieval_target(question, key, expectation)
    comparison = expectation["comparison"]
    threshold = expectation["threshold"]
    distance = expectation["deterministic_distance"]

    comparison_valid = ALLOWED_DISTANCE_COMPARISONS.include?(comparison)
    threshold_valid = threshold.is_a?(Numeric) && threshold.positive?
    distance_valid = valid_cosine_distance?(distance)

    unless comparison_valid
      errors << "Question #{key} has invalid distance comparison #{comparison.inspect}"
    end

    unless threshold_valid
      errors << "Question #{key} requires a positive numeric distance threshold"
    end

    unless distance_valid
      errors << "Question #{key} requires a finite deterministic cosine distance between 0 and 2"
    end

    return unless target_valid && comparison_valid && threshold_valid && distance_valid
    return unless [ true, false ].include?(question["expect_abstention"])

    retrieves = distance <= threshold
    validate_retrieved_target_is_expected(question, key, expectation, retrieves)

    if retrieves == question["expect_abstention"]
      errors << "Question #{key} distance expectation conflicts with expect_abstention"
    end
  end

  def validate_provider_threshold_expectation(question, key, expectation)
    target_valid = validate_retrieval_target(question, key, expectation)
    threshold = expectation["configured_distance_threshold"]
    deterministic = expectation["deterministic"]
    provider = expectation["provider"]

    threshold_valid = threshold.is_a?(Numeric) && threshold.positive?
    unless threshold_valid
      errors << "Question #{key} requires a positive numeric configured distance threshold"
    end

    unless deterministic.is_a?(Hash)
      errors << "Question #{key} requires a deterministic provider expectation"
    end

    unless provider.is_a?(Hash)
      errors << "Question #{key} requires a provider expectation"
    end

    return unless deterministic.is_a?(Hash) && provider.is_a?(Hash)

    should_retrieve = deterministic["should_retrieve"]
    distance = deterministic["distance"]
    behavior = provider["expected_behavior"]
    regression_note = provider["regression_note"]

    should_retrieve_valid = [ true, false ].include?(should_retrieve)
    distance_valid = valid_cosine_distance?(distance)

    unless should_retrieve_valid
      errors << "Question #{key} must define deterministic should_retrieve as true or false"
    end

    unless distance_valid
      errors << "Question #{key} requires a finite deterministic provider cosine distance between 0 and 2"
    end

    unless ALLOWED_PROVIDER_EXPECTED_BEHAVIORS.include?(behavior)
      errors << "Question #{key} has invalid provider expected behavior #{behavior.inspect}"
    end

    if regression_note.to_s.strip.empty?
      errors << "Question #{key} requires a provider regression note"
    end

    return unless target_valid && threshold_valid && should_retrieve_valid && distance_valid

    validate_retrieved_target_is_expected(question, key, expectation, should_retrieve)

    if should_retrieve != (distance <= threshold)
      errors << "Question #{key} deterministic provider result conflicts with its configured threshold"
    end

    if [ true, false ].include?(question["expect_abstention"]) &&
        should_retrieve == question["expect_abstention"]
      errors << "Question #{key} deterministic provider result conflicts with expect_abstention"
    end
  end

  def validate_expected_chunks_belong_to_question_scope(question, key)
    workspace_key = question["workspace_key"]
    user_key = question["user_key"]

    Array(question["expected_chunk_keys"]).each do |chunk_key|
      chunk = chunks_by_key[chunk_key]
      next unless chunk

      source = sources_by_key[chunk["source_key"]]
      next unless source

      if source["user_key"] != user_key
        errors << "Question #{key} expects chunk #{chunk_key} which belongs to a different user"
      end

      if !Array(source["workspace_keys"]).include?(workspace_key)
        errors << "Question #{key} expects chunk #{chunk_key} which belongs to a different workspace"
      end
    end
  end

  def validate_retrieval_target(question, key, expectation)
    target_key = expectation["target_chunk_key"]

    if target_key.to_s.strip.empty?
      errors << "Question #{key} retrieval expectation requires a target chunk key"
      return false
    end

    target = chunks_by_key[target_key]
    unless target
      errors << "Question #{key} references missing retrieval target chunk #{target_key}"
      return false
    end

    source = sources_by_key[target["source_key"]]
    return false unless source

    valid = true

    if source["user_key"] != question["user_key"]
      errors << "Question #{key} retrieval target chunk #{target_key} belongs to a different user"
      valid = false
    end

    unless Array(source["workspace_keys"]).include?(question["workspace_key"])
      errors << "Question #{key} retrieval target chunk #{target_key} belongs to a different workspace"
      valid = false
    end

    valid
  end

  def validate_retrieved_target_is_expected(question, key, expectation, should_retrieve)
    return unless should_retrieve
    return if Array(question["expected_chunk_keys"]).include?(expectation["target_chunk_key"])

    errors << "Question #{key} retrieval target chunk must be expected when retrieval should succeed"
  end

  def valid_cosine_distance?(value)
    return false unless value.is_a?(Numeric)

    distance = Float(value)
    distance.finite? && distance.between?(0, 2)
  rescue ArgumentError, TypeError
    false
  end

  def normalize_root(data)
    return data if data.is_a?(Hash)

    @structure_errors << "Dataset root must be a hash"
    {}
  end

  def normalize_collection(data, key, label)
    collection = data.fetch(key, [])

    unless collection.is_a?(Array)
      @structure_errors << "#{label} must be an array"
      return []
    end

    collection.each_with_index.filter_map do |record, index|
      if record.is_a?(Hash)
        record
      else
        @structure_errors << "#{label} entry at index #{index} must be a hash"
        nil
      end
    end
  end

  def check_duplicate_keys(records, field, label)
    keys = records.map { |record| record[field] }
    duplicates = keys.compact.tally.select { |_key, count| count > 1 }

    duplicates.each_key do |key|
      errors << "Duplicate #{label} key: #{key}"
    end
  end

  def reset_indexes
    @users_by_key = nil
    @workspaces_by_key = nil
    @sources_by_key = nil
    @chunks_by_key = nil
    @questions_by_key = nil
  end

  def users_by_key
    @users_by_key ||= index_by(users, "key")
  end

  def workspaces_by_key
    @workspaces_by_key ||= index_by(workspaces, "key")
  end

  def sources_by_key
    @sources_by_key ||= index_by(sources, "key")
  end

  def chunks_by_key
    @chunks_by_key ||= index_by(chunks, "key")
  end

  def questions_by_key
    @questions_by_key ||= index_by(questions, "key")
  end

  def index_by(records, field)
    records.each_with_object({}) do |record, index|
      index[record[field]] = record
    end
  end
end
