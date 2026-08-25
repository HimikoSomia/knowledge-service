class KnowledgeSourcesController < ApplicationController
  before_action :set_workspace
  before_action :set_knowledge_source, only: %i[edit update destroy]

  def new
    source_type = params[:source_type].presence_in(KnowledgeSource.source_types.keys) || "note"
    @knowledge_source = owned_sources.new(source_type: source_type)
  end

  def create
    @knowledge_source = owned_sources.new(knowledge_source_params)
    @knowledge_source.user = Current.user

    if @knowledge_source.save
      queued = @knowledge_source.enqueue_indexing!
      redirect_to workspace_path(@workspace),
                  status: :see_other,
                  notice: ("Knowledge source saved and queued for indexing." if queued),
                  alert: ("Knowledge source was saved, but indexing could not be queued." unless queued)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @knowledge_source.update(knowledge_source_params)
      queued = @knowledge_source.enqueue_indexing!
      redirect_to workspace_path(@workspace),
                  status: :see_other,
                  notice: ("Knowledge source updated and queued for indexing." if queued),
                  alert: ("Knowledge source was updated, but indexing could not be queued." unless queued)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @knowledge_source.destroy!
    redirect_to workspace_path(@workspace), status: :see_other, notice: "Knowledge source removed."
  end

  private

  def set_workspace
    @workspace = Current.user.workspaces.find(params[:workspace_id])
  end

  def set_knowledge_source
    @knowledge_source = owned_sources.find(params[:id])
  end

  def owned_sources
    @workspace.knowledge_sources.where(user: Current.user)
  end

  def knowledge_source_params
    params.expect(knowledge_source: %i[source_type title content])
  end
end
