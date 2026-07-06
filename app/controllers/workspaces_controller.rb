class WorkspacesController < ApplicationController
  before_action :set_workspace, only: [ :show, :edit, :update, :destroy ]

  def index
    @workspaces = Current.user.workspaces
  end

  def show
  end

  def new
    @workspace = Current.user.workspaces.new
  end

  def create
    @workspace = Current.user.workspaces.new(workspace_params)
    if @workspace.save
      redirect_to @workspace
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @workspace.update(workspace_params)
      redirect_to @workspace
    else
      render :edit
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

  def workspace_service
    @workspace_service ||= WorkspaceService.new(Current.user)
  end

  def workspace_params
    params.require(:workspace).permit(:name, :description)
  end
end
