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

  test "processed? returns true for processed status" do
    assert documents(:processed_doc).processed?
  end

  test "failed? returns true for failed status" do
    assert documents(:failed_doc).failed?
  end

  test "mark_processing! sets status and processing_started_at" do
    doc = documents(:pending_doc)
    freeze_time do
      doc.mark_processing!
      assert_equal "processing", doc.reload.status
      assert_in_delta Time.current, doc.processing_started_at, 1.second
    end
  end

  test "mark_processed! sets status, chunk_count, file_checksum, processed_at" do
    doc = documents(:pending_doc)
    freeze_time do
      doc.mark_processed!(5, "abc123")
      doc.reload
      assert_equal "processed", doc.status
      assert_equal 5, doc.chunk_count
      assert_equal "abc123", doc.file_checksum
      assert_in_delta Time.current, doc.processed_at, 1.second
      assert_nil doc.error_message
    end
  end

  test "mark_failed! sets status and error_message" do
    doc = documents(:pending_doc)
    doc.mark_failed!("Something went wrong")
    doc.reload
    assert_equal "failed", doc.status
    assert_equal "Something went wrong", doc.error_message
  end

  # --- Idempotency ---

  test "already_processed_for? is true when processed with same checksum" do
    doc = documents(:processed_doc)
    assert doc.already_processed_for?("abc123")
  end

  test "already_processed_for? is false when checksum differs" do
    doc = documents(:processed_doc)
    assert_not doc.already_processed_for?("different")
  end

  test "already_processed_for? is false when not yet processed" do
    doc = documents(:pending_doc)
    assert_not doc.already_processed_for?("abc123")
  end

  # --- Job enqueueing ---

  test "enqueues ProcessDocumentJob after create" do
    assert_enqueued_jobs 1, only: ProcessDocumentJob do
      doc = @user.documents.new(title: "Job Test")
      doc.file.attach(io: File.open(file_fixture("sample.txt")), filename: "sample.txt", content_type: "text/plain")
      doc.save!
    end
  end
end
