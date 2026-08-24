class AddProcessingAttemptTracking < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :processing_generation, :integer, null: false, default: 0
    add_column :documents, :processing_checksum, :string
    add_column :documents, :processing_job_id, :string
    add_column :documents, :processing_job_execution, :integer, null: false, default: 0

    add_column :document_chunks, :source_key, :string
    add_index :document_chunks,
              [ :document_id, :source_key ],
              unique: true,
              where: "source_key IS NOT NULL",
              name: "index_document_chunks_on_document_and_source_key"
  end
end
