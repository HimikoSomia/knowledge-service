class AddEnrichmentStatusToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :enrichment_status, :string, null: false, default: "not_applicable"
    add_column :documents, :enriched_at, :datetime
  end
end
