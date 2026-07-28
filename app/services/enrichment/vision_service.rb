# Abstract interface for vision-based image description services.
#
# Implementations should:
#   - Return a String description of the image, or nil if analysis fails.
#   - Re-extract the image from the source document using the image_ref metadata.
#   - Log their operations at the info/debug level.
#
# To implement a concrete backend:
#   1. Subclass Enrichment::VisionService.
#   2. Override #configured? to check for required credentials.
#   3. Override #describe_image_from_document to call the external API.
#
class Enrichment::VisionService
  # Returns true when the service has all required credentials/config.
  def configured?
    false
  end

  # Analyzes the image identified by image_ref within document and returns
  # a human-readable description string, or nil on failure.
  #
  # @param document [Document] the parent document (used to re-access the file)
  # @param image_ref [Hash] the image_ref section from extracted_content["sections"]
  # @return [String, nil]
  def describe_image_from_document(_document, _image_ref)
    raise NotImplementedError, "#{self.class}#describe_image_from_document is not implemented"
  end
end
