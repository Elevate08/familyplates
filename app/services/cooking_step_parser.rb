# One step per screen. Numbered lists, bare lines, and a run-on paragraph all come out the same.
class CookingStepParser
  Timer = Struct.new(:label, :seconds, keyword_init: true) do
    # Short tap-target label: "1 hr 30 min", "45 min".
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

    # Same shape the Stimulus controller writes, so the first paint does not reformat.
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

  # Headings are short. A long unnumbered line in a numbered recipe stays a step.
  MAX_HEADING_LENGTH = 80

  UNICODE_FRACTIONS = QuantityParser::UNICODE_FRACTIONS

  # "for 15 minutes", "20-25 minutes". The countdown uses the low end; the high end is only for the label.
  DURATION = /
    (?<qty>\d+\s*[#{UNICODE_FRACTIONS.keys.join}]|\d+(?:\.\d+)?(?:\s+\d\/\d)?|\d\/\d|[#{UNICODE_FRACTIONS.keys.join}])
    (?:\s*(?:-|–|—|\s+to\s+|\s+or\s+)\s*(?<high>\d+(?:\.\d+)?))?
    \s*
    (?<unit>hours?|hrs?|minutes?|mins?|seconds?|secs?)\b
  /xi

  UNIT_SECONDS = { "h" => 3600, "m" => 60, "s" => 1 }.freeze

  # Under 10 seconds is a figure of speech. Over 12 hours is an overnight rest, not a counter timer.
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
    # A trailing heading ("Enjoy!") would vanish, so the tail is always a step.
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

  # A heading ends in a colon, or — only when steps are numbered — a short unnumbered line ("Make the filling").
  def heading?(line, numbered_count)
    return false if line.length > MAX_HEADING_LENGTH

    line.end_with?(":") || numbered_count.positive?
  end

  # A single line of several sentences was never marked up. Split it or Cook Mode shows one wall of text.
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
    QuantityParser.parse(raw)
  end
end
