class CreateDocumentChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :document_chunks do |t|
      t.references :document, null: false, foreign_key: true

      t.integer :chunk_index, null: false
      t.text :content, null: false

      t.vector :embedding, limit: 1536
      t.string :embedding_model

      t.integer :token_count
      t.integer :page_number
      t.integer :start_char
      t.integer :end_char

      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :document_chunks, [:document_id, :chunk_index], unique: true
  end
end
