class WorkspaceQuestionRetriesController < ApplicationController
  before_action :set_workspace
  before_action :set_workspace_question

  def create
    unless @workspace_question.failed?
      respond_not_retryable
      return
    end

    queued = @workspace_question.retry_answer!
    respond_to do |format|
      format.html do
        redirect_to workspace_question_path(@workspace, @workspace_question),
                    status: :see_other,
                    notice: ("Answer generation was queued again." if queued),
                    alert: ("The answer could not be queued. Please try again." unless queued)
      end
      format.json do
        render json: question_payload,
               status: queued ? :accepted : :service_unavailable,
               location: workspace_question_url(@workspace, @workspace_question)
      end
    end
  end

  private

  def set_workspace
    @workspace = Current.user.workspaces.find(params[:workspace_id])
  end

  def set_workspace_question
    @workspace_question = @workspace.workspace_questions
                                    .where(user: Current.user)
                                    .find(params[:question_id])
  end

  def respond_not_retryable
    respond_to do |format|
      format.html do
        redirect_to workspace_question_path(@workspace, @workspace_question),
                    status: :see_other,
                    alert: "Only failed questions can be retried."
      end
      format.json { render json: { error: "not_retryable" }, status: :unprocessable_entity }
    end
  end

  def question_payload
    {
      id: @workspace_question.id,
      workspace_id: @workspace_question.workspace_id,
      status: @workspace_question.reload.status,
      error_code: @workspace_question.error_code
    }
  end
end
