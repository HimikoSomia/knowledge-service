class ConsolidateDocumentProcessingStatuses < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE documents
      SET status = CASE
        WHEN status = 'failed' OR enrichment_status = 'failed' OR embedding_status = 'failed' THEN 'failed'
        WHEN embedding_status = 'embedded' THEN 'ready'
        WHEN embedding_status = 'embedding' THEN 'embedding'
        WHEN enrichment_status = 'enriching' THEN 'enriching'
        ELSE status
      END
    SQL

    remove_column :documents, :enrichment_status, :string
    remove_column :documents, :embedding_status, :string
  end

  def down
    add_column :documents, :enrichment_status, :string, null: false, default: "not_applicable"
    add_column :documents, :embedding_status, :string, null: false, default: "not_started"

    execute <<~SQL.squish
      UPDATE documents
      SET embedding_status = CASE
            WHEN status = 'ready' THEN 'embedded'
            WHEN status = 'embedding' THEN 'embedding'
            ELSE 'not_started'
          END,
          enrichment_status = CASE
            WHEN status = 'enriching' THEN 'enriching'
            WHEN enriched_at IS NOT NULL THEN 'enriched'
            ELSE 'not_applicable'
          END,
          status = CASE
            WHEN status IN ('ready', 'embedding', 'enriching') THEN 'processed'
            ELSE status
          END
    SQL
  end
end
