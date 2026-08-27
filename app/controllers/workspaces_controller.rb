class WorkspacesController < ApplicationController
  before_action :set_workspace, only: [ :show, :edit, :update, :destroy, :search ]

  def index
    @workspaces = Current.user.workspaces.includes(:documents).order(updated_at: :desc)
  end

  def show
    prepare_workspace_knowledge
  end

  def search
    prepare_workspace_knowledge
    @query = params[:q].to_s.strip

    if @query.present?
      service = Retrieval::WorkspaceKnowledgeSearchService.new(Current.user)
      begin
        @results = service.search(@query, limit: 10, workspace_id: @workspace.id)
        @search_performed = true
      rescue Retrieval::WorkspaceKnowledgeSearchService::NotConfiguredError
        @search_error = "Search is not available yet. Knowledge embedding must be configured first."
      rescue => e
        Rails.logger.error "WorkspacesController#search failed (#{e.class})"
        @search_error = "Search failed. Please try again."
      end
    end

    render :show
  end

  def new
    @workspace = Current.user.workspaces.new
  end

  def create
    @workspace = Current.user.workspaces.new(workspace_params)
    if @workspace.save
      redirect_to @workspace
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @workspace.update(workspace_params)
      redirect_to @workspace
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @workspace.destroy
    redirect_to workspaces_path
  end

  private

  def set_workspace
    @workspace = Current.user.workspaces.find(params[:id])
  end

  def workspace_params
    params.require(:workspace).permit(:name, :description)
  end

  def prepare_workspace_knowledge
    @knowledge_sources = @workspace.knowledge_sources.where(user: Current.user).recent_first
  end
end
