# Shared concern for all document-processing jobs.
# Provides safe error logging (full details to logs) and user-friendly messages
# stored in the database.
module DocumentProcessingLogging
  extend ActiveSupport::Concern

  # Logs the full exception (class + message + first 10 backtrace lines) and
  # returns a generic, user-safe message suitable for storing in error_message.
  def log_and_friendly_message(exception, context:)
    Rails.logger.error(
      "[#{self.class.name}] #{context} — #{exception.class}: #{exception.message}\n" \
      "  Backtrace:\n  #{exception.backtrace&.first(10)&.join("\n  ")}"
    )

    friendly_message_for(exception)
  end

  private

  def friendly_message_for(exception)
    case exception
    when Embedding::OpenAiEmbeddingService::RateLimitError
      "Embedding service is temporarily rate-limited. Processing will retry automatically."
    when Embedding::OpenAiEmbeddingService::ServiceError
      "Embedding service is temporarily unavailable. Processing will retry automatically."
    when Embedding::OpenAiEmbeddingService::ConfigurationError
      "Embedding service is not configured. Please check the application settings."
    when Embedding::OpenAiEmbeddingService::InvalidInputError
      "A chunk could not be embedded due to invalid content."
    when Timeout::Error, Faraday::TimeoutError, Faraday::ConnectionFailed
      "Processing timed out. It will be retried automatically."
    when ActiveRecord::RecordNotFound
      "Document not found."
    else
      "Processing failed. The issue has been logged and will be investigated."
    end
  end
end
