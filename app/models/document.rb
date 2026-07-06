class Document < ApplicationRecord
  has_one_attached :file
  belongs_to :user
  has_many :document_workspaces, dependent: :destroy
  has_many :workspaces, through: :document_workspaces
  has_many :document_chunks, dependent: :destroy
end
