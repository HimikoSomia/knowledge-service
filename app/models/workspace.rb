class Workspace < ApplicationRecord
  has_many :document_workspaces, dependent: :destroy
  has_many :documents, through: :document_workspaces
end
