# What the operator console tracks about a household: suspension and
# operational tags.
module Household::Operations
  def suspended?
    suspended_at.present?
  end

  def operational_tag_list
    (operational_tags || "").split(",").map(&:strip).reject(&:blank?)
  end

  def add_operational_tag(tag)
    cleaned = tag.to_s.strip.downcase.gsub(/[^a-z0-9_-]/, "")
    return if cleaned.blank?

    current_tags = operational_tag_list
    return if current_tags.include?(cleaned)

    self.operational_tags = (current_tags + [ cleaned ]).join(",")
  end

  def remove_operational_tag(tag)
    cleaned = tag.to_s.strip.downcase.gsub(/[^a-z0-9_-]/, "")
    current_tags = operational_tag_list
    self.operational_tags = current_tags.reject { |t| t == cleaned }.join(",")
  end

  def has_operational_tag?(tag)
    operational_tag_list.include?(tag.to_s.strip.downcase)
  end
end
