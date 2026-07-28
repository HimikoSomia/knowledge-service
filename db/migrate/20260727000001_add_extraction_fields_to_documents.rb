class AddExtractionFieldsToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :extracted_content, :jsonb, null: false, default: {}
    add_column :documents, :file_checksum, :string
    add_column :documents, :processing_started_at, :datetime
  end
end
