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
    latest = HomebrewAgeGate::Package.new(
      type: :cask,
      name: "some-app",
      tap: "homebrew/cask",
      source_path: "Casks/s/some-app.rb",
      tap_git_head: "abc",
      version: "latest",
      auto_updates: true
    )

    assert latest.cask?
    assert latest.latest_cask?
    assert latest.auto_updates_cask?
  end
end

