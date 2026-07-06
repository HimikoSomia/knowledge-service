class WorkspaceService
  def initialize(user)
    @user = user
  end

  def create_workspace(params = {})
    workspace = @user.workspaces.create(name: params[:name], description: params[:description])
    if workspace.persisted?
      if params[:document_ids].present?
        documents = @user.documents.where(id: params[:document_ids])
        workspace.documents << documents
      end
      if params[:documents].present?
        params[:documents].each do |document_params|
          document = @user.documents.create(title: document_params[:title], document_type: document_params[:document_type])
          workspace.documents << document if document.persisted?
        end
      end
      workspace
    else
      workspace
    end
  end

  def add_document_to_workspace(workspace, document)
    workspace.documents << document
  end

  def remove_document_from_workspace(workspace, document)
    workspace.documents.delete(document)
  end
end
