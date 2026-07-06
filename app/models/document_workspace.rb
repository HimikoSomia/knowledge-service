class DocumentWorkspace < ApplicationRecord
  belongs_to :document
  belongs_to :workspace
end
