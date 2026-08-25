require "test_helper"

class KnowledgeSourceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @workspace = workspaces(:workspace_one)
  end

  test "validates title content and supported source type" do
    source = @workspace.knowledge_sources.new(user: @user, source_type: "note", title: "", content: "")

    assert_not source.valid?
    assert source.errors[:title].any?
    assert source.errors[:content].any?

    source.title = "Valid"
    source.content = "Useful context"
    source.source_type = "unsupported"
    assert_not source.valid?
    assert source.errors[:source_type].any?
  end

  test "rejects a workspace owned by another user" do
    source = KnowledgeSource.new(
      user: @user,
      workspace: workspaces(:workspace_two),
      source_type: "memo",
      title: "Cross-user memo",
      content: "Should not save"
    )

    assert_not source.valid?
    assert source.errors[:workspace].any?
  end

  test "destroy removes associated chunks" do
    source = knowledge_sources(:note_one)

    assert_difference -> { KnowledgeChunk.count }, -1 do
      source.destroy!
    end
  end

  test "enqueue_indexing creates one generation-bound job claim" do
    source = @workspace.knowledge_sources.create!(
      user: @user,
      source_type: "note",
      title: "Queue me",
      content: "Index this content"
    )

    assert_enqueued_jobs 1, only: IndexKnowledgeSourceJob do
      assert source.enqueue_indexing!
    end

    source.reload
    assert source.pending?
    assert_equal 1, source.indexing_generation
    assert source.indexing_job_id.present?
    assert_equal 0, source.indexing_job_execution
  end

  test "only the current job can claim an indexing generation" do
    source = knowledge_sources(:note_one)
    source.update_columns(
      status: "pending",
      indexing_generation: 3,
      indexing_job_id: "current-job",
      indexing_job_execution: 0
    )

    assert_not source.claim_indexing!(generation: 2, job_id: "old-job", execution: 1)
    assert source.claim_indexing!(generation: 3, job_id: "current-job", execution: 1)
    assert_not source.claim_indexing!(generation: 3, job_id: "duplicate-job", execution: 1)
    assert source.reload.indexing?
  end

  test "enqueue failure records a safe terminal state" do
    source = @workspace.knowledge_sources.create!(
      user: @user,
      source_type: "note",
      title: "Queue failure",
      content: "Keep this content"
    )
    job = Object.new
    job.define_singleton_method(:job_id) { "failed-job" }
    job.define_singleton_method(:enqueue) { raise ActiveJob::EnqueueError, "adapter unavailable" }
    IndexKnowledgeSourceJob.define_singleton_method(:new) { |*| job }

    assert_not source.enqueue_indexing!

    source.reload
    assert source.failed?
    assert_equal "queue_unavailable", source.error_code
    assert_nil source.indexing_job_id
  ensure
    if IndexKnowledgeSourceJob.singleton_class.method_defined?(:new, false)
      IndexKnowledgeSourceJob.singleton_class.remove_method(:new)
    end
  end
end
