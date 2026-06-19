# frozen_string_literal: true

require_relative "test_helper"

class PackageTest < Minitest::Test
  def test_canonical_name_includes_tap_when_present
    package = HomebrewAgeGate::Package.new(
      type: :formula,
      name: "jq",
      tap: "homebrew/core",
      source_path: "Formula/j/jq.rb",
      tap_git_head: "abc",
      version: "1.0",
      auto_updates: false
    )

    assert_equal "homebrew/core/jq", package.canonical_name
  end

  def test_cask_policy_helpers
    package = HomebrewAgeGate::Package.new(
      type: :cask,
      name: "some-app",
      tap: "homebrew/cask",
      source_path: "Casks/s/some-app.rb",
      tap_git_head: "abc",
      version: "latest",
      auto_updates: true
    )

    assert package.cask?
    assert package.auto_updates_cask?
  end

  def test_package_info_extracts_installed_versions
    formula = HomebrewAgeGate::Package.from_formula_info(
      "name" => "jq",
      "tap" => "homebrew/core",
      "versions" => { "stable" => "1.8.1" },
      "ruby_source_path" => "Formula/j/jq.rb",
      "tap_git_head" => "abc",
      "installed" => [{ "version" => "1.8.0" }, { "version" => "1.8.0" }]
    )
    cask = HomebrewAgeGate::Package.from_cask_info(
      "token" => "some-app",
      "tap" => "homebrew/cask",
      "version" => "2.0.0",
      "ruby_source_path" => "Casks/s/some-app.rb",
      "tap_git_head" => "abc",
      "installed" => "1.9.0"
    )

    assert_equal ["1.8.0"], formula.installed_versions
    assert_equal ["1.9.0"], cask.installed_versions
  end
end
