module WorkspacesHelper
  def workspace_question_error_message(question)
    case question.error_code
    when "not_configured"
      "Answer generation is not configured. Please contact the application administrator."
    when "provider_unavailable"
      "The answer service is temporarily unavailable. Please try again."
    when "queue_unavailable"
      "The answer could not be queued. Please try again."
    when "invalid_response"
      "The answer service returned an unusable response. Please try a different question."
    else
      "The answer could not be generated. Please try again."
    end
  end
end
