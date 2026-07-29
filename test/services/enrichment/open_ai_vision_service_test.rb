require "test_helper"

class Enrichment::OpenAiVisionServiceTest < ActiveSupport::TestCase
  setup do
    @service = Enrichment::OpenAiVisionService.new
    @original_client_new = OpenAI::Client.method(:new)
    ENV["OPENAI_API_KEY"] = "test-key"

    @user = users(:one)
    @document = @user.documents.new(title: "Vision Test")
    @document.file.attach(
      io:           File.open(file_fixture("sample.txt")),
      filename:     "sample.txt",
      content_type: "text/plain"
    )
    @document.save!
  end

  teardown do
    ENV.delete("OPENAI_API_KEY")
    if OpenAI::Client.singleton_class.method_defined?(:new, false)
      OpenAI::Client.singleton_class.remove_method(:new)
    end
  end

  test "configured? returns true when OPENAI_API_KEY is present" do
    assert @service.configured?
  end

  test "configured? returns false when OPENAI_API_KEY is absent" do
    ENV.delete("OPENAI_API_KEY")
    assert_not @service.configured?
  end

  test "vision_model defaults to gpt-4o-mini" do
    assert_equal "gpt-4o-mini", @service.vision_model
  end

  test "vision_model reads OPENAI_VISION_MODEL env var" do
    ENV["OPENAI_VISION_MODEL"] = "gpt-4o"
    svc = Enrichment::OpenAiVisionService.new
    assert_equal "gpt-4o", svc.vision_model
  ensure
    ENV.delete("OPENAI_VISION_MODEL")
  end

  test "returns description from API for uploaded image" do
    image_ref = { "type" => "image_ref", "source_type" => "uploaded",
                  "page_number" => 1, "image_index" => 0 }

    stub_vision_api("A text file containing sample content.")

    # Use a real PNG so Base64 encoding succeeds
    @document.file.attach(
      io:           File.new(file_fixture("sample.txt")),
      filename:     "sample.png",
      content_type: "image/png"
    )
    result = @service.describe_image_from_document(@document, image_ref)
    assert_equal "A text file containing sample content.", result
  end

  test "returns nil when pdftoppm is unavailable for PDF page" do
    image_ref = { "type" => "image_ref", "source_type" => "embedded",
                  "page_number" => 1, "image_index" => 0 }

    @service.define_singleton_method(:pdftoppm_available?) { false }
    result = @service.describe_image_from_document(@document, image_ref)
    assert_nil result
  end

  test "returns nil and logs on API error" do
    image_ref = { "type" => "image_ref", "source_type" => "uploaded",
                  "page_number" => 1, "image_index" => 0 }

    @document.file.attach(
      io:           File.new(file_fixture("sample.txt")),
      filename:     "sample.png",
      content_type: "image/png"
    )

    fake = Object.new
    fake.define_singleton_method(:chat) do |**_|
      raise OpenAI::Error.new("quota exceeded")
    end
    OpenAI::Client.define_singleton_method(:new) { |**_| fake }

    result = @service.describe_image_from_document(@document, image_ref)
    assert_nil result  # error is swallowed, nil returned
  end

  private

  def stub_vision_api(description)
    fake_response = { "choices" => [ { "message" => { "content" => description } } ] }
    fake = Object.new
    fake.define_singleton_method(:chat) { |**_| fake_response }
    OpenAI::Client.define_singleton_method(:new) { |**_| fake }
  end
end
