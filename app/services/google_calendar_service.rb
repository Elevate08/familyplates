require "google/apis/calendar_v3"
require "googleauth"

class GoogleCalendarService
  attr_reader :household, :calendar_id

  def self.credentials_json(household = nil)
    household&.google_service_account_json.presence ||
      ENV["GOOGLE_CALENDAR_SERVICE_ACCOUNT_JSON"].presence ||
      Rails.application.credentials.google_calendar_service_account_json.presence ||
      (File.exist?(Rails.root.join("config/google_service_account.json")) ? File.read(Rails.root.join("config/google_service_account.json")) : nil) ||
      Household.where.not(google_service_account_json: [ nil, "" ]).first&.google_service_account_json
  end

  def self.configured?(household = nil)
    credentials_json(household).present?
  end

  def self.service_account_email(household = nil)
    raw = credentials_json(household)
    return nil if raw.blank?

    begin
      data = JSON.parse(raw)
      data["client_email"]
    rescue StandardError
      nil
    end
  end

  def initialize(household)
    @household = household
    @calendar_id = household.google_calendar_id
  end

  def configured?
    self.class.configured?(household)
  end

  def service_account_email
    self.class.service_account_email(household)
  end

  def credentials_json
    self.class.credentials_json(household)
  end

  def test_connection(target_calendar_id = nil)
    cal_id = target_calendar_id.presence || calendar_id
    return { success: false, error: "No Google Calendar ID specified." } if cal_id.blank?
    return { success: false, error: "Google Service Account JSON key is missing. Paste your Service Account JSON in the field below." } unless configured?

    begin
      calendar = client.get_calendar(cal_id)
      { success: true, summary: calendar.summary }
    rescue StandardError => e
      { success: false, error: e.message }
    end
  end

  def create_or_update_event(slot)
    return unless household.google_calendar_enabled? && calendar_id.present? && self.class.configured?
    return if slot.display_title == "No Meal Planned"

    event_data = build_event_data(slot)
    start_time, end_time = calculate_slot_times(slot)

    event = Google::Apis::CalendarV3::Event.new(
      summary: event_data[:summary],
      description: event_data[:description],
      start: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: start_time.iso8601,
        time_zone: Time.zone.name
      ),
      end: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: end_time.iso8601,
        time_zone: Time.zone.name
      )
    )

    if slot.google_event_id.present?
      begin
        result = client.update_event(calendar_id, slot.google_event_id, event)
      rescue Google::Apis::ClientError => e
        # If event was deleted on Google Calendar, recreate it
        if e.status_code == 404
          result = client.insert_event(calendar_id, event)
          slot.update_column(:google_event_id, result.id)
        else
          raise e
        end
      end
    else
      result = client.insert_event(calendar_id, event)
      slot.update_column(:google_event_id, result.id)
    end
  rescue StandardError => e
    Rails.logger.error("GoogleCalendarService error for Slot ##{slot.id}: #{e.message}")
  end

  def delete_event(slot)
    return unless slot&.google_event_id.present?

    delete_event_by_id(slot.google_event_id)
    slot.update_column(:google_event_id, nil)
  end

  def delete_event_by_id(event_id)
    return unless calendar_id.present? && event_id.present? && configured?

    begin
      client.delete_event(calendar_id, event_id)
    rescue Google::Apis::ClientError => e
      # Ignore 404 if already deleted on Google Calendar
      Rails.logger.warn("GoogleCalendar event 404 on delete: #{e.message}") unless e.status_code == 404
    rescue StandardError => e
      Rails.logger.error("GoogleCalendarService delete error for event #{event_id}: #{e.message}")
    end
  end

  def sync_meal_plan(meal_plan)
    return 0 unless household.google_calendar_enabled? && calendar_id.present? && configured?

    count = 0
    meal_plan.meal_plan_slots.includes(:recipe, :family_member).each do |slot|
      if slot.display_title == "No Meal Planned"
        delete_event(slot) if slot.google_event_id.present?
      else
        create_or_update_event(slot)
        count += 1
      end
    end
    count
  end

  def calculate_slot_times(slot)
    time_str = slot.scheduled_time.presence ||
      case slot.meal_type
      when "breakfast" then household.breakfast_time.presence || "08:00"
      when "lunch"     then household.lunch_time.presence || "12:30"
      else                  household.dinner_time.presence || "18:00"
      end

    duration_minutes = case slot.meal_type
    when "breakfast" then 45
    when "lunch"     then 45
    else                  60
    end

    hour, min = time_str.split(":").map(&:to_i)
    start_time = Time.zone.local(slot.date.year, slot.date.month, slot.date.day, hour, min, 0)
    end_time = start_time + duration_minutes.minutes

    [ start_time, end_time ]
  end

  def build_event_data(slot)
    meal_type_tag = slot.meal_type.capitalize
    cook_tag = slot.cook_name.present? ? " (Cook: #{slot.cook_name})" : ""
    summary = "🍽️ #{meal_type_tag}: #{slot.display_title}#{cook_tag}"

    desc_lines = []
    desc_lines << "👨‍🍳 Cook: #{slot.cook_name || 'Family'}"

    if slot.recipe
      r = slot.recipe
      desc_lines << "⏱️ Prep: #{r.prep_time}m | Cook: #{r.cook_time}m | Servings: #{r.servings}"
      if r.recipe_ingredients.any?
        desc_lines << "\n📋 Ingredients:"
        r.recipe_ingredients.each do |ing|
          desc_lines << "• #{ing.quantity} #{ing.unit} #{ing.name}".strip
        end
      end
    end

    desc_lines << "\n📝 Notes: #{slot.notes}" if slot.notes.present?

    {
      summary: summary,
      description: desc_lines.join("\n")
    }
  end

  private

  def client
    @client ||= begin
      calendar_service = Google::Apis::CalendarV3::CalendarService.new
      calendar_service.client_options.application_name = "FamilyPlates"

      json_key = StringIO.new(self.class.credentials_json)
      authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: json_key,
        scope: [ Google::Apis::CalendarV3::AUTH_CALENDAR ]
      )
      calendar_service.authorization = authorizer
      calendar_service
    end
  end
end
