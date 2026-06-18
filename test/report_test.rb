# frozen_string_literal: true

require_relative "test_helper"

class ReportTest < Minitest::Test
  def test_format_decision_prints_definition_commit_date
    package = HomebrewAgeGate::Package.new(
      type: :formula,
      name: "jq",
      tap: "homebrew/core",
      source_path: "Formula/j/jq.rb",
      tap_git_head: "abc123",
      version: "1.7.1",
      auto_updates: false
    )
    decision = HomebrewAgeGate::Decision.new(
      package: package,
      allowed: true,
      reason: "old enough",
      age_result: HomebrewAgeGate::AgeResult.new(
        known: true,
        commit_time: Time.utc(2026, 6, 10, 15, 30, 0),
        age_seconds: 8 * 86_400,
        reason: nil
      )
    )

    assert_equal(
      "homebrew/core/jq age=8.00d definition_commit_date=2026-06-10 reason=old enough",
      HomebrewAgeGate::Report.format_decision(decision)
    )
  end

  def test_format_decision_prints_unknown_definition_commit_date
    package = HomebrewAgeGate::Package.new(
      type: :formula,
      name: "missing",
      tap: "homebrew/core",
      source_path: "Formula/m/missing.rb",
      tap_git_head: "abc123",
      version: "1.0",
      auto_updates: false
    )
    decision = HomebrewAgeGate::Decision.new(
      package: package,
      allowed: false,
      reason: "unknown age: no git history",
      age_result: HomebrewAgeGate::AgeResult.new(
        known: false,
        commit_time: nil,
        age_seconds: nil,
        reason: "no git history"
      )
    )

    assert_equal(
      "homebrew/core/missing age=unknown definition_commit_date=unknown reason=unknown age: no git history",
      HomebrewAgeGate::Report.format_decision(decision)
    )
  end
end
