class WorkspacesController < ApplicationController
  before_action :set_workspace, only: [ :show, :edit, :update, :destroy ]

  def index
    @workspaces = Workspace.all
  end

  def show
  end

  def new
    @workspace = Workspace.new
  end

  def create
    @workspace = Workspace.new(workspace_params)
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
    @workspace = Workspace.find(params[:id])
  end

  def workspace_params
    params.expect(workspace: [ :name, :description ])
  end
end
