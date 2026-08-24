module DocumentsHelper
  ENRICHMENT_STATUS_LABELS = {
    "not_required" => "Not required",
    "pending" => "Pending",
    "in_progress" => "In progress",
    "succeeded" => "Complete",
    "skipped" => "Skipped",
    "partial" => "Partial",
    "failed" => "Not completed"
  }.freeze

  def enrichment_status_label(document)
    ENRICHMENT_STATUS_LABELS.fetch(document.enrichment_status, document.enrichment_status.humanize)
  end

  def enrichment_status_badge_class(document)
    class_names(
      "badge badge-sm font-medium",
      case document.enrichment_status
      when "succeeded"
        "badge-success"
      when "pending", "in_progress"
        "badge-info"
      when "skipped", "partial"
        "badge-warning"
      when "failed"
        "badge-error"
      else
        "badge-ghost"
      end
    )
  end
end
