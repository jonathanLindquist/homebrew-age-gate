# frozen_string_literal: true

require_relative "test_helper"

class DryRunParserTest < Minitest::Test
  def test_parses_names_and_ignores_headings_warnings_and_versions
    output = <<~TEXT
      Warning: something from Homebrew
      ==> Would upgrade 2 outdated packages:
      homebrew/core/oldpkg 1.0 -> 2.0
      - homebrew/cask/slack 4.0 -> 5.0
      1 package would be cleaned
      Disable this behaviour by setting `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1`.
    TEXT

    assert_equal(
      ["homebrew/core/oldpkg", "homebrew/cask/slack"],
      HomebrewAgeGate::DryRunParser.new.parse_package_names(output)
    )
  end

  def test_returns_unique_names
    output = "homebrew/core/oldpkg 1.0 -> 2.0\nhomebrew/core/oldpkg 1.0 -> 2.0\n"

    assert_equal ["homebrew/core/oldpkg"], HomebrewAgeGate::DryRunParser.new.parse_package_names(output)
  end
end

