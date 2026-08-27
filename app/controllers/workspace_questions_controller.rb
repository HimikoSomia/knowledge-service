class WorkspaceQuestionsController < ApplicationController
  before_action :set_workspace
  before_action :set_workspace_question, only: :show
  rate_limit to: 10, within: 1.minute, only: :create,
             with: -> { render_rate_limited }

  def index
    prepare_question_index
    @workspace_question = owned_questions.new(user: Current.user)

    respond_to do |format|
      format.html
      format.json { render json: @workspace_questions.map { |question| question_payload(question) } }
    end
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: question_payload(@workspace_question) }
    end
  end

  def create
    @workspace_question = owned_questions.new(workspace_question_params)
    @workspace_question.user = Current.user

    if @workspace_question.save
      queued = @workspace_question.enqueue_answer!
      respond_to do |format|
        format.html do
          redirect_to workspace_questions_path(@workspace, anchor: "workspace_question_#{@workspace_question.id}"),
                      status: :see_other,
                      alert: ("The answer could not be queued. Please try again." unless queued)
        end
        format.json do
          render json: question_payload(@workspace_question.reload),
                 status: queued ? :accepted : :service_unavailable,
                 location: workspace_question_url(@workspace, @workspace_question)
        end
      end
    else
      respond_to do |format|
        format.html do
          prepare_question_index
          render :index, status: :unprocessable_entity
        end
        format.json { render json: { errors: @workspace_question.errors.to_hash }, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_workspace
    @workspace = Current.user.workspaces.find(params[:workspace_id])
  end

  def set_workspace_question
    @workspace_question = owned_questions.find(params[:id])
  end

  def owned_questions
    @workspace.workspace_questions.where(user: Current.user)
  end

  def workspace_question_params
    params.expect(workspace_question: [ :question ])
  end

  def prepare_question_index
    @workspace_questions = owned_questions.recent_first.limit(50)
  end

  def question_payload(question)
    {
      id: question.id,
      workspace_id: question.workspace_id,
      question: question.question,
      answer: question.answer,
      status: question.status,
      answer_model: question.answer_model,
      citations: question.citations,
      error_code: question.error_code,
      answered_at: question.answered_at,
      created_at: question.created_at
    }
  end

  def render_rate_limited
    respond_to do |format|
      format.html do
        redirect_to @workspace ? workspace_questions_path(@workspace) : root_path,
                    alert: "Too many questions. Please try again shortly."
      end
      format.json { render json: { error: "rate_limited" }, status: :too_many_requests }
    end
  end
end
