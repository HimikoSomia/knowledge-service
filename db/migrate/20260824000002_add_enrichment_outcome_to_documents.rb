class AddEnrichmentOutcomeToDocuments < ActiveRecord::Migration[8.1]
  ENRICHMENT_STATUSES = %w[not_required pending in_progress succeeded skipped partial failed].freeze

  def change
    add_column :documents, :enrichment_status, :string, null: false, default: "not_required"
    add_check_constraint :documents,
                         "enrichment_status IN (#{ENRICHMENT_STATUSES.map { |status| quote(status) }.join(', ')})",
                         name: "documents_enrichment_status_check"

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE documents
          SET enrichment_status = 'succeeded'
          WHERE enriched_at IS NOT NULL
        SQL

        execute <<~SQL.squish
          UPDATE documents
          SET enrichment_status = 'in_progress'
          WHERE status = 'enriching'
        SQL
      end
    end
  end
end
