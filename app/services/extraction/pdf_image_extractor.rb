require "open3"

# Extracts images from a PDF page using poppler-utils (pdfimages, pdftoppm)
# and attempts OCR on each extracted image via OcrService.
#
# For each sparse page (few words of native text) this service:
#   1. Tries to extract embedded image XObjects with pdfimages.
#   2. Falls back to rendering the full page with pdftoppm when no XObjects are found.
#   3. Runs OcrService on each image large enough to contain meaningful content.
#   4. Returns paragraph sections for OCR-able images and image_ref sections for others.
#
# Degrades gracefully when poppler-utils is not installed.
class Extraction::PdfImageExtractor
  # Images below this file-size threshold are likely decorative (icon, bullet, etc.)
  MIN_IMAGE_BYTES = 10_000  # ~10 KB
  # Resolution for page rendering (DPI)
  RENDER_DPI = "300"

  # Returns true when at least one required poppler binary is on PATH.
  def available?
    return @available_cache if defined?(@available_cache)
    @available_cache = pdfimages_available? || pdftoppm_available?
  end

  # Extract content from a single page of a PDF.
  # Returns an array of section hashes (paragraph or image_ref).
  def extract_from_page(pdf_path, page_number:)
    Dir.mktmpdir("ks_pdf_imgs_") do |tmpdir|
      image_paths = extract_embedded_images(pdf_path, page_number: page_number, tmpdir: tmpdir)

      if image_paths.empty? && pdftoppm_available?
        # No embedded images found — render the entire page and OCR it.
        image_paths = render_page(pdf_path, page_number: page_number, tmpdir: tmpdir)
      end

      build_sections(image_paths, page_number: page_number)
    end
  end

  private

  # --- image extraction ---

  def extract_embedded_images(pdf_path, page_number:, tmpdir:)
    return [] unless pdfimages_available?

    prefix = File.join(tmpdir, "img")
    _out, err, status = Open3.capture3(
      "pdfimages",
      "-f", page_number.to_s,
      "-l", page_number.to_s,
      "-j", "-png",
      pdf_path.to_s,
      prefix
    )

    unless status.success?
      Rails.logger.warn "PdfImageExtractor: pdfimages failed for page #{page_number}: #{err.strip}"
      return []
    end

    Dir.glob(File.join(tmpdir, "img-*.{jpg,jpeg,png,ppm,pbm}"))
       .select { |p| large_enough?(p) }
  end

  def render_page(pdf_path, page_number:, tmpdir:)
    prefix = File.join(tmpdir, "page")
    _out, err, status = Open3.capture3(
      "pdftoppm",
      "-f", page_number.to_s,
      "-l", page_number.to_s,
      "-r", RENDER_DPI,
      "-png",
      pdf_path.to_s,
      prefix
    )

    unless status.success?
      Rails.logger.warn "PdfImageExtractor: pdftoppm failed for page #{page_number}: #{err.strip}"
      return []
    end

    Dir.glob(File.join(tmpdir, "page-*.png"))
  end

  # --- section building ---

  def build_sections(image_paths, page_number:)
    return [] if image_paths.empty?

    ocr = Extraction::OcrService.new
    sections = []

    image_paths.each_with_index do |image_path, idx|
      if ocr.available?
        result = ocr.ocr(image_path)
        if ocr.meaningful?(result)
          sections << {
            "type"        => "paragraph",
            "content"     => result[:text],
            "page_number" => page_number,
            "source_type" => "ocr"
          }
          next
        end
      end

      # Image did not yield meaningful OCR text — preserve as a reference.
      sections << {
        "type"           => "image_ref",
        "page_number"    => page_number,
        "image_index"    => idx,
        "source_type"    => "embedded",
        "skipped_reason" => ocr.available? ? "low_text_density" : "ocr_unavailable"
      }
    end

    sections
  end

  # --- helpers ---

  def large_enough?(path)
    File.size(path) >= MIN_IMAGE_BYTES
  rescue
    false
  end

  def pdfimages_available?
    @pdfimages ||= system("which pdfimages > /dev/null 2>&1")
  end

  def pdftoppm_available?
    @pdftoppm ||= system("which pdftoppm > /dev/null 2>&1")
  end
end
