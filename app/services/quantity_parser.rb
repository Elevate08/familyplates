# frozen_string_literal: true

# Parses quantities and fractions from ingredient strings and cooking instructions,
# supporting unicode vulgar fractions, ASCII fractions, mixed numbers, and decimals.
class QuantityParser
  UNICODE_FRACTIONS = {
    "¼" => 0.25,
    "½" => 0.5,
    "¾" => 0.75,
    "⅐" => 1.0 / 7,
    "⅑" => 1.0 / 9,
    "⅒" => 0.1,
    "⅓" => 1.0 / 3,
    "⅔" => 2.0 / 3,
    "⅕" => 0.2,
    "⅖" => 0.4,
    "⅗" => 0.6,
    "⅘" => 0.8,
    "⅙" => 1.0 / 6,
    "⅚" => 5.0 / 6,
    "⅛" => 0.125,
    "⅜" => 0.375,
    "⅝" => 0.625,
    "⅞" => 0.875
  }.freeze

  UNICODE_FRACTIONS_PATTERN = Regexp.union(UNICODE_FRACTIONS.keys)

  def self.parse(raw)
    return 0.0 if raw.blank?

    normalized = raw.to_s.gsub(UNICODE_FRACTIONS_PATTERN) { |match| " #{match} " }
    parts = normalized.strip.split(/\s+/)
    total = 0.0

    parts.each do |part|
      if (fraction = UNICODE_FRACTIONS[part])
        total += fraction
      elsif part.include?("/")
        numerator, denominator = part.split("/").map(&:to_f)
        total += (denominator.zero? ? 0.0 : numerator / denominator)
      else
        total += part.to_f
      end
    end

    total
  end

  def self.parse_fraction(raw)
    return 1.0 if raw.blank?

    total = parse(raw)
    total.positive? ? total.round(2) : 1.0
  end
end
