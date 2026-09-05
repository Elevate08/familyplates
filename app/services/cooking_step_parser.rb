# Turns a recipe's free-text instructions into discrete steps for Cook Mode.
#
# Instructions reach the database in whatever shape they arrived in: the scraper
# writes "1. …\n\n2. …" with section headings on their own lines, a person typing
# a family recipe writes one line per step with no numbering at all, and an older
# import can be a single run-on paragraph. Cook Mode shows one step at a time on
# a counter-top screen, so it needs all three to come out the same way.
class CookingStepParser
  Timer = Struct.new(:label, :seconds, keyword_init: true) do
    # "1 hr 30 min", "45 min", "1 min 30 sec" - short enough for a tap target.
    def display
      hours, rest = seconds.divmod(3600)
      minutes, secs = rest.divmod(60)

      if hours.positive?
        minutes.zero? ? "#{hours} hr" : "#{hours} hr #{minutes} min"
      elsif minutes.positive?
        secs.zero? ? "#{minutes} min" : "#{minutes} min #{secs} sec"
      else
        "#{secs} sec"
      end
    end

    # The countdown's starting face, in the same shape the Stimulus controller
    # will keep writing, so the first paint does not visibly reformat.
    def clock
      hours, rest = seconds.divmod(3600)
      minutes, secs = rest.divmod(60)

      hours.positive? ? format("%d:%02d:%02d", hours, minutes, secs) : format("%d:%02d", minutes, secs)
    end
  end

  Step = Struct.new(:number, :text, :section, :timers, keyword_init: true) do
    def section? = section.present?
    def timers? = timers.present?
  end

  # A step marker the writer put there: "1.", "2)", "Step 3:".
  STEP_MARKER = /\A(?:step\s*)?(\d+)\s*[.):]\s+/i

  # A heading is a short line, so a long unnumbered paragraph in a numbered
  # recipe stays a step rather than becoming a title nobody can read.
  MAX_HEADING_LENGTH = 80

  UNICODE_FRACTIONS = { "½" => 0.5, "¼" => 0.25, "¾" => 0.75, "⅓" => 1.0 / 3, "⅔" => 2.0 / 3 }.freeze

  # "for 15 minutes", "20-25 minutes", "1 1/2 hours", "about 90 seconds". The
  # second quantity of a range is captured only so the label can show it: the
  # countdown uses the low end, which is when a cook wants to look at the pan.
  DURATION = /
    (?<qty>\d+(?:\.\d+)?(?:\s+\d\/\d)?|\d\/\d|[#{UNICODE_FRACTIONS.keys.join}])
    (?:\s*(?:-|–|—|\s+to\s+|\s+or\s+)\s*(?<high>\d+(?:\.\d+)?))?
    \s*
    (?<unit>hours?|hrs?|minutes?|mins?|seconds?|secs?)\b
  /xi

  UNIT_SECONDS = { "h" => 3600, "m" => 60, "s" => 1 }.freeze

  # Below ten seconds is a figure of speech ("a few seconds"), and past twelve
  # hours it is an overnight rest nobody stands at the counter for.
  MIN_TIMER_SECONDS = 10
  MAX_TIMER_SECONDS = 12 * 60 * 60
  MAX_TIMERS_PER_STEP = 3

  def self.call(instructions)
    new(instructions).steps
  end

  def initialize(instructions)
    @instructions = instructions.to_s
  end

  def steps
    @steps ||= build_steps
  end

  private

  attr_reader :instructions

  def build_steps
    lines = instructions.split(/\r?\n/).map(&:strip).reject(&:blank?)
    return [] if lines.empty?

    entries = classify(lines)
    # A heading with nothing under it ("Enjoy!" after the last step) would be
    # swallowed whole, so the tail is always a step.
    entries.last[:kind] = :step if entries.last[:kind] == :heading
    entries = split_single_paragraph(entries) if entries.count { |e| e[:kind] == :step } <= 1

    section = nil
    number = 0

    entries.filter_map do |entry|
      if entry[:kind] == :heading
        section = entry[:text]
        next
      end

      number += 1
      Step.new(number: number, text: entry[:text], section: section, timers: timers_in(entry[:text]))
    end
  end

  def classify(lines)
    numbered = lines.count { |line| line.match?(STEP_MARKER) }

    lines.map do |line|
      if line.match?(STEP_MARKER)
        { kind: :step, text: line.sub(STEP_MARKER, "").strip }
      elsif heading?(line, numbered)
        { kind: :heading, text: line.chomp(":").strip }
      else
        { kind: :step, text: line }
      end
    end
  end

  # Two shapes count as a heading: anything ending in a colon, and - only in a
  # recipe whose steps are numbered - a short line that carries no number, which
  # is how "Make the filling" arrives between "2." and "3.".
  def heading?(line, numbered_count)
    return false if line.length > MAX_HEADING_LENGTH

    line.end_with?(":") || numbered_count.positive?
  end

  # One long line holding several sentences is a paste from a site that never
  # marked its steps up. Splitting it is the difference between Cook Mode
  # showing one wall of text and showing a recipe.
  def split_single_paragraph(entries)
    entries.flat_map do |entry|
      next entry unless entry[:kind] == :step

      sentences = entry[:text].split(/(?<=[.!?])\s+(?=[A-Z0-9])/).map(&:strip).reject(&:blank?)
      next entry if sentences.length < 2

      sentences.map { |sentence| { kind: :step, text: sentence } }
    end
  end

  def timers_in(text)
    found = []

    text.scan(DURATION) do
      match = Regexp.last_match
      seconds = duration_seconds(match[:qty], match[:unit])
      next if seconds.nil?
      next if found.any? { |timer| timer.seconds == seconds }

      found << Timer.new(label: match[0].strip.squeeze(" "), seconds: seconds)
      break if found.length >= MAX_TIMERS_PER_STEP
    end

    found
  end

  def duration_seconds(quantity, unit)
    amount = parse_quantity(quantity)
    return nil if amount.nil? || amount <= 0

    seconds = (amount * UNIT_SECONDS.fetch(unit[0].downcase)).round
    return nil if seconds < MIN_TIMER_SECONDS || seconds > MAX_TIMER_SECONDS

    seconds
  end

  def parse_quantity(raw)
    raw.to_s.split(/\s+/).sum do |part|
      if (fraction = UNICODE_FRACTIONS[part])
        fraction
      elsif part.include?("/")
        numerator, denominator = part.split("/").map(&:to_f)
        denominator.zero? ? 0 : numerator / denominator
      else
        part.to_f
      end
    end
  end
end
