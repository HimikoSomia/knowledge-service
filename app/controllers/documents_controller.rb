class DocumentsController < ApplicationController
  include Pagy::Method

  before_action :set_document, only: [ :show, :edit, :update, :destroy ]
  before_action :set_workspaces, only: [ :new, :edit, :create, :update ]

  def index
    limit = params[:limit] || 10
    @pagy, @documents = pagy(Current.user.documents.includes(:workspaces).order(created_at: :desc), items: limit)
  end

  def show
  end

  def new
    @document = Current.user.documents.new
  end

  def create
    @document = Current.user.documents.new(document_params)
    if @document.save
      assign_workspaces(@document)
      redirect_to @document, notice: "Document uploaded. Processing will begin shortly."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @selected_workspace_ids = @document.workspace_ids
  end

  def update
    if @document.update(document_params)
      assign_workspaces(@document)
      redirect_to @document
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @document.destroy
    redirect_to documents_path, status: :see_other
  end

  private

  def set_document
    @document = Current.user.documents.find(params[:id])
  end

  def set_workspaces
    @workspaces = Current.user.workspaces.order(:name)
  end

  def document_params
    params.expect(document: [ :title, :file ])
  end

  # Safely assigns workspaces from the form, scoped to the current user's
  # workspaces to prevent IDOR via submitted IDs.
  def assign_workspaces(document)
    requested_ids = Array(params.dig(:document, :workspace_ids))
                      .reject(&:blank?)
                      .map(&:to_i)

    return unless params[:document]&.key?(:workspace_ids) || requested_ids.any?

    safe_workspaces = Current.user.workspaces.where(id: requested_ids)
    document.workspaces = safe_workspaces
  end
end
