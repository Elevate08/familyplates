# frozen_string_literal: true

require "test_helper"

class QuantityParserTest < ActiveSupport::TestCase
  test "parses integers and decimals" do
    assert_equal 2.0, QuantityParser.parse("2")
    assert_equal 1.5, QuantityParser.parse("1.5")
    assert_equal 2.0, QuantityParser.parse_fraction("2")
    assert_equal 1.5, QuantityParser.parse_fraction("1.5")
  end

  test "parses ASCII fractions and mixed numbers" do
    assert_equal 0.5, QuantityParser.parse("1/2")
    assert_equal 1.5, QuantityParser.parse("1 1/2")
    assert_equal 0.5, QuantityParser.parse_fraction("1/2")
    assert_equal 1.5, QuantityParser.parse_fraction("1 1/2")
  end

  test "parses unicode fractions including eighths" do
    assert_equal 0.5, QuantityParser.parse("½")
    assert_equal 0.25, QuantityParser.parse("¼")
    assert_equal 0.75, QuantityParser.parse("¾")
    assert_in_delta 0.333, QuantityParser.parse("⅓"), 0.001
    assert_in_delta 0.666, QuantityParser.parse("⅔"), 0.001
    assert_equal 0.125, QuantityParser.parse("⅛")
    assert_equal 0.375, QuantityParser.parse("⅜")
    assert_equal 0.625, QuantityParser.parse("⅝")
    assert_equal 0.875, QuantityParser.parse("⅞")
  end

  test "parses mixed numbers with unicode fractions" do
    assert_equal 1.5, QuantityParser.parse("1 ½")
    assert_equal 1.5, QuantityParser.parse("1½")
    assert_equal 1.125, QuantityParser.parse("1 ⅛")
    assert_equal 1.125, QuantityParser.parse("1⅛")
  end

  test "parse_fraction rounds to 2 decimals and defaults to 1.0 for blank" do
    assert_equal 1.0, QuantityParser.parse_fraction(nil)
    assert_equal 1.0, QuantityParser.parse_fraction("")
    assert_equal 0.13, QuantityParser.parse_fraction("⅛")
    assert_equal 0.33, QuantityParser.parse_fraction("⅓")
    assert_equal 0.67, QuantityParser.parse_fraction("⅔")
  end
end
