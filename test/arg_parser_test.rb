# frozen_string_literal: true

require_relative "test_helper"

class ArgParserTest < Minitest::Test
  def test_unknown_flags_fail_closed
    error = assert_raises(HomebrewAgeGate::ArgParseError) do
      HomebrewAgeGate::ArgParser.new.parse(["upgrade", "--new-homebrew-flag", "jq"])
    end

    assert_match(/Unsupported or unsafe/, error.message)
  end

  def test_parses_known_flags_and_outdated_subset
    parsed = HomebrewAgeGate::ArgParser.new.parse(["upgrade", "--formula", "--minimum-version", "1.2.3", "--no-ask", "jq"])

    assert_equal ["--formula", "--minimum-version", "1.2.3", "--no-ask"], parsed.flags
    assert_equal ["--formula", "--minimum-version", "1.2.3"], parsed.outdated_flags
    assert_equal ["jq"], parsed.names
  end

  def test_parses_inline_value_flags
    parsed = HomebrewAgeGate::ArgParser.new.parse(["upgrade", "--min-version=1.2.3", "jq"])

    assert_equal ["--min-version=1.2.3"], parsed.flags
    assert_equal ["--min-version=1.2.3"], parsed.outdated_flags
    assert_equal ["jq"], parsed.names
  end

  def test_missing_value_flags_fail_closed
    error = assert_raises(HomebrewAgeGate::ArgParseError) do
      HomebrewAgeGate::ArgParser.new.parse(["upgrade", "--minimum-version"])
    end

    assert_match(/requires a value/, error.message)
  end

  def test_double_dash_fails_closed
    error = assert_raises(HomebrewAgeGate::ArgParseError) do
      HomebrewAgeGate::ArgParser.new.parse(["upgrade", "--", "jq"])
    end

    assert_match(/ambiguous/, error.message)
  end

  def test_dry_run_is_removed_from_final_flags
    parsed = HomebrewAgeGate::ArgParser.new.parse(["upgrade", "--dry-run", "--no-ask", "jq"])

    assert parsed.dry_run?
    assert_equal ["--no-ask"], parsed.flags_without_dry_run
  end
end
