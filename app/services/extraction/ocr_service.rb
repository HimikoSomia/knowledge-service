require "open3"
require "timeout"

# Thin wrapper around the system Tesseract OCR binary.
# Degrades gracefully when the binary is not installed.
class Extraction::OcrService
  # Minimum word count for an OCR result to be considered meaningful.
  MIN_WORD_COUNT = 10
  # Per-image OCR timeout in seconds.
  TIMEOUT_SECONDS = 30

  # Returns true when the tesseract binary is available on PATH.
  def available?
    return @available_cache if defined?(@available_cache)
    @available_cache = system("which tesseract > /dev/null 2>&1")
  end

  # Runs OCR on the given image file path.
  # Returns: { text: String, word_count: Integer, available: Boolean }
  # Never raises — errors are logged and return empty text.
  def ocr(image_path)
    unless available?
      Rails.logger.debug { "OcrService: Tesseract not available, skipping #{image_path}" }
      return { text: "", word_count: 0, available: false }
    end

    text = run_tesseract(image_path.to_s)
    { text: text, word_count: text.split.size, available: true }
  rescue => e
    Rails.logger.error "OcrService: unexpected error for #{image_path}: #{e.message}"
    { text: "", word_count: 0, available: true, error: e.message }
  end

  # Returns true when the OCR result contains enough words to be useful.
  def meaningful?(result)
    result[:word_count].to_i >= MIN_WORD_COUNT
  end

  private

  def run_tesseract(image_path)
    text = ""
    Timeout.timeout(TIMEOUT_SECONDS) do
      stdout, stderr, status = Open3.capture3(
        "tesseract", image_path, "stdout",
        "-l", "eng",
        "--psm", "3"   # fully automatic page segmentation
      )
      unless status.success?
        Rails.logger.warn "OcrService: tesseract non-zero exit for #{image_path}: #{stderr.strip}"
      end
      text = stdout.strip
    end
    text
  rescue Timeout::Error
    Rails.logger.error "OcrService: tesseract timed out (#{TIMEOUT_SECONDS}s) for #{image_path}"
    ""
  end
end
