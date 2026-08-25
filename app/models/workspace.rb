class Workspace < ApplicationRecord
  belongs_to :user
  has_many :document_workspaces, dependent: :destroy
  has_many :documents, through: :document_workspaces
  has_many :workspace_questions, dependent: :destroy
  has_many :knowledge_sources, dependent: :destroy

  validates :name, presence: true
end
