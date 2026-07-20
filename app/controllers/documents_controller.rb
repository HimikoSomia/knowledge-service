class DocumentsController < ApplicationController
  include Pagy::Method

  before_action :set_document, only: [ :show, :edit, :update, :destroy ]

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
      redirect_to @document
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @document.update(document_params)
      redirect_to @document
    else
      render :edit
    end
  end

  def destroy
    @document.destroy
    redirect_to documents_path
  end

  private

  def set_document
    @document = Current.user.documents.find(params[:id])
  end

  def document_params
    params.expect(document: [ :title, :document_type ])
  end
end
