# frozen_string_literal: true

require_relative "test_helper"

require "stringio"

class ReportTest < Minitest::Test
  GREEN = "\e[38;2;119;221;119m"
  RED = "\e[38;2;255;154;162m"
  BOLD_WHITE = "\e[1;97m"
  RESET = "\e[0m"

  def test_print_plan_separates_allowed_and_skipped_groups
    io = StringIO.new

    HomebrewAgeGate::Report.print_plan(plan_with_allowed_and_skipped, io: io)

    assert_equal(<<~OUTPUT, io.string)
      homebrew-age-gate plan

      Allowed:
        homebrew/core/oldpkg age=8d definition_commit_date=2026-06-10 reason=old enough

      Skipped:
        homebrew/core/youngpkg age=2d definition_commit_date=2026-06-16 reason=too new
    OUTPUT
  end

  def test_print_plan_styles_group_headings_and_package_names_when_color_enabled
    io = StringIO.new

    HomebrewAgeGate::Report.print_plan(plan_with_allowed_and_skipped, io: io, color: true)

    assert_includes io.string, "#{BOLD_WHITE}Allowed:#{RESET}"
    assert_includes io.string, "#{BOLD_WHITE}Skipped:#{RESET}"
    assert_includes io.string, "#{GREEN}homebrew/core/oldpkg#{RESET} #{BOLD_WHITE}age#{RESET}=8d"
    assert_includes io.string, "#{BOLD_WHITE}definition_commit_date#{RESET}=2026-06-10"
    assert_includes io.string, "#{BOLD_WHITE}reason#{RESET}=old enough"
    assert_includes io.string, "#{RED}homebrew/core/youngpkg#{RESET} #{BOLD_WHITE}age#{RESET}=2d"
  end

  def test_print_deferred_preflight_styles_root_and_blocked_dependency_names
    io = StringIO.new
    root = HomebrewAgeGate::UpgradePreflight::DeferredRoot.new(
      package: package("oldpkg"),
      blocked_decisions: [decision("youngdep", allowed: false, reason: "too new", age_days: 2, commit_time: Time.utc(2026, 6, 16))]
    )

    HomebrewAgeGate::Report.print_deferred_preflight([root], io: io, color: true)

    assert_includes(
      io.string,
      "#{GREEN}homebrew/core/oldpkg#{RESET} blocked because dry-run includes blocked packages: #{RED}homebrew/core/youngdep#{RESET} (too new)"
    )
    assert_includes io.string, "#{RED}homebrew/core/youngdep#{RESET} #{BOLD_WHITE}age#{RESET}=2d"
  end

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
      "homebrew/core/jq age=8d definition_commit_date=2026-06-10 reason=old enough",
      HomebrewAgeGate::Report.format_decision(decision)
    )
  end

  def test_format_decision_rounds_age_to_nearest_integer_day
    decision = decision("nearly-nine", allowed: true, reason: "old enough", age_days: 8.6, commit_time: Time.utc(2026, 6, 10))

    assert_includes HomebrewAgeGate::Report.format_decision(decision), "age=9d"
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

  private

  def plan_with_allowed_and_skipped
    HomebrewAgeGate::Plan.new(
      parsed_args: nil,
      decisions: [
        decision("oldpkg", allowed: true, reason: "old enough", age_days: 8, commit_time: Time.utc(2026, 6, 10)),
        decision("youngpkg", allowed: false, reason: "too new", age_days: 2, commit_time: Time.utc(2026, 6, 16))
      ]
    )
  end

  def decision(name, allowed:, reason:, age_days:, commit_time:)
    HomebrewAgeGate::Decision.new(
      package: package(name),
      allowed: allowed,
      reason: reason,
      age_result: HomebrewAgeGate::AgeResult.new(
        known: true,
        commit_time: commit_time,
        age_seconds: age_days * 86_400,
        reason: nil
      )
    )
  end

  def package(name)
    HomebrewAgeGate::Package.new(
      type: :formula,
      name: name,
      tap: "homebrew/core",
      source_path: "Formula/#{name[0]}/#{name}.rb",
      tap_git_head: "abc123",
      version: "1.0",
      auto_updates: false
    )
  end
end
