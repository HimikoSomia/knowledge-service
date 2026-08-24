class WorkspacesController < ApplicationController
  before_action :set_workspace, only: [ :show, :edit, :update, :destroy, :search ]

  def index
    @workspaces = Current.user.workspaces.includes(:documents).order(updated_at: :desc)
  end

  def show
  end

  def search
    @query = params[:q].to_s.strip

    if @query.present?
      service = Retrieval::DocumentSearchService.new(Current.user)
      begin
        @results = service.search(@query, limit: 10, workspace_id: @workspace.id)
                          .includes(:document)
        @search_performed = true
      rescue Retrieval::DocumentSearchService::NotConfiguredError
        @search_error = "Search is not available yet. Document embedding must be configured first."
      rescue => e
        Rails.logger.error "WorkspacesController#search: #{e.message}"
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
end
