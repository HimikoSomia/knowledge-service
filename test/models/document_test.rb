require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  # --- Validations ---

  test "valid with title and attached file" do
    doc = @user.documents.new(title: "Test Doc")
    doc.file.attach(io: File.open(file_fixture("sample.txt")), filename: "sample.txt", content_type: "text/plain")
    assert doc.valid?
  end

  test "invalid without title" do
    doc = @user.documents.new
    doc.file.attach(io: File.open(file_fixture("sample.txt")), filename: "sample.txt", content_type: "text/plain")
    assert_not doc.valid?
    assert_includes doc.errors[:title], "can't be blank"
  end

  test "invalid without file on create" do
    doc = @user.documents.new(title: "No File")
    assert_not doc.valid?
    assert doc.errors[:file].any?
  end

  test "invalid with unsupported MIME type" do
    doc = @user.documents.new(title: "Exec")
    doc.file.attach(io: StringIO.new("#!/bin/bash"), filename: "evil.sh", content_type: "application/x-sh")
    assert_not doc.valid?
    assert doc.errors[:file].any? { |m| m.include?("not supported") }
  end

  test "invalid when file exceeds 50 MB" do
    doc = @user.documents.new(title: "Huge File")
    doc.file.attach(io: StringIO.new("x"), filename: "big.txt", content_type: "text/plain")
    doc.file.blob.define_singleton_method(:byte_size) { 51.megabytes.to_i }
    assert_not doc.valid?
    assert doc.errors[:file].any? { |m| m.include?("too large") }
  end

  test "invalid with unknown status" do
    doc = @user.documents.new(title: "Test", status: "unknown")
    doc.file.attach(io: File.open(file_fixture("sample.txt")), filename: "sample.txt", content_type: "text/plain")
    assert_not doc.valid?
    assert_includes doc.errors[:status], "is not included in the list"
  end

  test "invalid with unknown enrichment status" do
    doc = @user.documents.new(title: "Test", enrichment_status: "unknown")
    doc.file.attach(io: File.open(file_fixture("sample.txt")), filename: "sample.txt", content_type: "text/plain")
    assert_not doc.valid?
    assert_includes doc.errors[:enrichment_status], "is not included in the list"
  end

  # --- document_type auto-detection ---

  test "detects document_type from content_type on save" do
    doc = @user.documents.new(title: "Text File")
    doc.file.attach(io: File.open(file_fixture("sample.txt")), filename: "sample.txt", content_type: "text/plain")
    doc.save!
    assert_equal "txt", doc.document_type
  end

  test "detects document_type from filename extension when content_type is generic" do
    doc = @user.documents.new(title: "CSV File")
    doc.file.attach(io: File.open(file_fixture("sample.csv")), filename: "sample.csv", content_type: "application/octet-stream")
    doc.save!
    assert_equal "csv", doc.document_type
  end

  # --- Status helpers ---

  test "pending? returns true for pending status" do
    assert documents(:pending_doc).pending?
  end

  test "ready? returns true for a searchable document" do
    assert documents(:processed_doc).ready?
  end

  test "failed? returns true for failed status" do
    assert documents(:failed_doc).failed?
  end

  # --- Job enqueueing ---

  test "enqueues ProcessDocumentJob after create" do
    assert_enqueued_jobs 1, only: ProcessDocumentJob do
      doc = @user.documents.new(title: "Job Test")
      doc.file.attach(io: File.open(file_fixture("sample.txt")), filename: "sample.txt", content_type: "text/plain")
      doc.save!
    end
  end

  test "a current stage claim cannot fail a newer file generation" do
    doc = documents(:pending_doc)
    doc.update_columns(
      processing_generation: 3,
      processing_job_id: "new-job",
      processing_job_execution: 0,
      status: "pending"
    )

    assert_not doc.fail_current_processing!(generation: 2, job_id: "old-job", message: "stale failure")
    assert_equal "pending", doc.reload.status
    assert_nil doc.error_message
  end

  test "replacing a file before extraction queues a new generation" do
    doc = @user.documents.new(title: "Replace Before Extraction")
    doc.file.attach(io: File.open(file_fixture("sample.txt")), filename: "sample.txt", content_type: "text/plain")
    doc.save!
    original_generation = doc.reload.processing_generation
    clear_enqueued_jobs

    assert_enqueued_with(job: ProcessDocumentJob) do
      doc.file.attach(
        io: StringIO.new("replacement document content"),
        filename: "replacement.txt",
        content_type: "text/plain"
      )
    end

    doc.reload
    assert_equal original_generation + 1, doc.processing_generation
    assert_equal doc.file.blob.checksum, doc.processing_checksum
    assert_equal "pending", doc.status
    assert doc.enrichment_not_required?
    assert_nil doc.enriched_at
  end
end
