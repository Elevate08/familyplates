class ActivityEvent < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :household
  belongs_to :actor, class_name: "FamilyMember", optional: true

  validates :event_type, :source, presence: true

  EVENT_VERBS = {
    "created" => "created",
    "updated" => "updated",
    "deleted" => "deleted",
    "imported" => "imported",
    "completed" => "completed",
    "generated" => "generated",
    "connected" => "connected",
    "synced" => "synced"
  }.freeze

  def self.track!(household:, event_type:, actor: nil, target: nil, source: "web", metadata: {})
    details = metadata.stringify_keys
    details["target_name"] ||= target_name_for(target)

    create!(
      household: household,
      actor: actor,
      event_type: event_type,
      source: source,
      target_type: target&.class&.base_class&.name,
      target_id: target&.id&.to_s,
      metadata: details
    )
  end

  def human_description
    return "FamilyPlates synced the calendar" if event_type == "calendar.synced"

    namespace, action = event_type.to_s.split(".", 2)
    actor_name = actor&.name || "FamilyPlates"
    verb = EVENT_VERBS.fetch(action, action.to_s.humanize.downcase)
    target_name = metadata.to_h["target_name"]

    if target_name.present?
      "#{actor_name} #{verb} #{namespace.to_s.singularize.humanize.downcase} #{target_name}"
    else
      "#{actor_name} #{verb} #{namespace.to_s.humanize.downcase}"
    end
  end

  private

  def self.target_name_for(target)
    return if target.nil?
    return target.title if target.respond_to?(:title)
    return target.name if target.respond_to?(:name)

    target.to_s
  end
end
