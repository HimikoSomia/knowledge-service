module ApplicationHelper
  def sidebar_link_class(controller)
    class_names(
      "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition",
      controller_name == controller ? "bg-primary text-primary-content shadow-sm" : "text-base-content/70 hover:bg-base-200 hover:text-base-content"
    )
  end

  def status_badge_class(status)
    class_names(
      "badge badge-sm font-medium capitalize",
      case status
      when "processed", "embedded"
        "badge-success"
      when "processing"
        "badge-info"
      when "failed", "error"
        "badge-error"
      else
        "badge-ghost"
      end
    )
  end

  # Returns a badge showing the embedding readiness of a document.
  def embedding_status_badge(document)
    label, css = case document.embedding_status
    when "embedded"        then [ "Searchable",    "badge-success" ]
    when "embedding"       then [ "Embedding…",    "badge-info" ]
    when "pending"         then [ "Queued",         "badge-ghost" ]
    when "failed"          then [ "Embed failed",   "badge-error" ]
    when "not_configured"  then [ "Not configured", "badge-ghost" ]
    when "not_applicable"  then [ nil, nil ]  # no badge for empty documents
    else                        [ nil, nil ]
    end

    return "" if label.nil?

    content_tag(:span, label, class: "badge badge-xs font-medium #{css}")
  end

  def short_date_time(value)
    return "Never" unless value

    value.strftime("%b %d, %Y")
  end
end
