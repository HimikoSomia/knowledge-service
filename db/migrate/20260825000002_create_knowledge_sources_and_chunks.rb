class CreateKnowledgeSourcesAndChunks < ActiveRecord::Migration[8.1]
  SOURCE_TYPES = %w[note memo].freeze
  STATUSES = %w[pending indexing ready unindexed failed].freeze

  def change
    create_table :knowledge_sources do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :source_type, null: false
      t.string :title, null: false
      t.text :content, null: false
      t.string :status, null: false, default: "pending"
      t.string :error_code
      t.integer :indexing_generation, null: false, default: 0
      t.string :indexing_job_id
      t.integer :indexing_job_execution, null: false, default: 0
      t.datetime :indexed_at
      t.timestamps
    end

    add_check_constraint :knowledge_sources,
                         "source_type IN (#{SOURCE_TYPES.map { |type| quote(type) }.join(', ')})",
                         name: "knowledge_sources_type_check"
    add_check_constraint :knowledge_sources,
                         "status IN (#{STATUSES.map { |status| quote(status) }.join(', ')})",
                         name: "knowledge_sources_status_check"
    add_index :knowledge_sources, [ :workspace_id, :created_at ]
    add_index :knowledge_sources, [ :user_id, :created_at ]
    add_index :knowledge_sources, [ :workspace_id, :source_type ]
    add_index :knowledge_sources, [ :status, :created_at ]

    create_table :knowledge_chunks do |t|
      t.references :knowledge_source, null: false, foreign_key: true
      t.integer :chunk_index, null: false
      t.text :content, null: false
      t.string :content_checksum, null: false
      t.integer :token_count
      t.vector :embedding, limit: 1536
      t.string :embedding_model
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :knowledge_chunks, [ :knowledge_source_id, :chunk_index ],
              unique: true,
              name: "index_knowledge_chunks_on_source_and_chunk"
    add_index :knowledge_chunks, [ :knowledge_source_id, :embedding_model ],
              name: "index_knowledge_chunks_on_source_and_model"
  end
end
