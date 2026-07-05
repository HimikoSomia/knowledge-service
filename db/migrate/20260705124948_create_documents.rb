class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.string :title, null: false
      t.string :document_type
      t.string :status, null: false, default: "pending"
      t.integer :chunk_count, default: 0
      t.datetime :processed_at
      t.datetime :embedded_at
      t.text :error_message
      t.timestamps
    end

    create_table :document_workspaces do |t|
      t.references :document, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.timestamps
    end

    add_index :documents, [:status, :created_at]
    add_index :document_workspaces, [:workspace_id, :document_id], unique: true
  end
end
