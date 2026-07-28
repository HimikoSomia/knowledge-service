# Extracts content from uploaded image files (JPEG, PNG, WEBP, GIF, TIFF, etc.)
# by running local OCR via OcrService.
#
# When OCR yields meaningful text the result is a normal paragraph section.
# When OCR is unavailable or yields little text, the image is preserved as an
# image_ref section for optional later enrichment by EnrichDocumentJob.
class Extraction::ImageExtractor < Extraction::BaseExtractor
  def extract(tempfile)
    ocr = Extraction::OcrService.new

    if ocr.available?
      result = ocr.ocr(tempfile.path)

      if ocr.meaningful?(result)
        sections = [ { "type"        => "paragraph",
                       "content"     => result[:text],
                       "page_number" => 1,
                       "source_type" => "ocr" } ]
        metadata = { "extractor" => "image", "word_count" => result[:word_count], "ocr_applied" => true }
        return build_result(raw_text: result[:text], sections: sections, metadata: metadata)
      end
    end

    # OCR unavailable or yielded too little — preserve as image_ref for enrichment.
    Rails.logger.info "ImageExtractor: image contains little or no readable text — storing as image_ref"
    sections = [ {
      "type"           => "image_ref",
      "page_number"    => 1,
      "image_index"    => 0,
      "source_type"    => "uploaded",
      "skipped_reason" => ocr.available? ? "low_text_density" : "ocr_unavailable"
    } ]
    metadata = { "extractor" => "image", "ocr_applied" => ocr.available? }
    build_result(raw_text: "", sections: sections, metadata: metadata)
  end
end
