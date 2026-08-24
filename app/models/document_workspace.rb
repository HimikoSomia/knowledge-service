class DocumentWorkspace < ApplicationRecord
  belongs_to :document
  belongs_to :workspace

  validates :document_id, uniqueness: { scope: :workspace_id }
  validate :document_and_workspace_have_same_owner

  private

  def document_and_workspace_have_same_owner
    return if document.blank? || workspace.blank?
    return if document.user.present? && document.user == workspace.user

    errors.add(:workspace, "must belong to the same user as the document")
  end
end
