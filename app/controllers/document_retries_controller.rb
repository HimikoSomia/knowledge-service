class DocumentRetriesController < ApplicationController
  before_action :set_document

  def create
    unless @document.failed?
      respond_not_retryable
      return
    end

    queued = @document.retry_processing!
    respond_to do |format|
      format.html do
        redirect_to @document,
                    status: :see_other,
                    notice: ("Document processing was queued again." if queued),
                    alert: ("Document processing could not be queued. Please try again." unless queued)
      end
      format.json do
        render json: document_payload,
               status: queued ? :accepted : :service_unavailable,
               location: document_url(@document)
      end
    end
  end

  private

  def set_document
    @document = Current.user.documents.find(params[:document_id])
  end

  def respond_not_retryable
    respond_to do |format|
      format.html do
        redirect_to @document,
                    status: :see_other,
                    alert: "Only failed documents can be retried."
      end
      format.json { render json: { error: "not_retryable" }, status: :unprocessable_entity }
    end
  end

  def document_payload
    {
      id: @document.id,
      status: @document.reload.status,
      error_message: @document.error_message
    }
  end
end
