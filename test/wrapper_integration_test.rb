# frozen_string_literal: true

require_relative "test_helper"

class WrapperIntegrationTest < Minitest::Test
  def test_upgrade_uses_allowlist_freezes_env_and_never_calls_bare_upgrade
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(dir, "Formula/o/oldpkg.rb" => 10)
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_json(scenario_path, {
        "repos" => { "homebrew/core" => tap_repo },
        "outdated" => {
          "formulae" => [{ "name" => "oldpkg" }],
          "casks" => []
        },
        "formulae" => [
          formula_info("oldpkg", tap: "homebrew/core", path: "Formula/o/oldpkg.rb", head: head)
        ],
        "casks" => [],
        "dry_run_output" => "==> Would upgrade 1 outdated package:\nhomebrew/core/oldpkg 1.0 -> 2.0\n"
      })

      stdout, stderr, status = run_bin(
        ["bin/brew", "upgrade"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      assert status.success?, stderr
      assert_match(/homebrew-age-gate plan/, stdout)

      calls = read_log(log_path)
      assert_includes calls.map { |entry| entry["args"] }, ["outdated", "--json=v2"]
      assert_includes calls.map { |entry| entry["args"] }, ["upgrade", "--dry-run", "homebrew/core/oldpkg"]
      assert_includes calls.map { |entry| entry["args"] }, ["upgrade", "homebrew/core/oldpkg"]
      refute_includes calls.map { |entry| entry["args"] }, ["upgrade"]

      final_call = calls.find { |entry| entry["args"] == ["upgrade", "homebrew/core/oldpkg"] }
      assert_equal "1", final_call.fetch("env").fetch("HOMEBREW_NO_AUTO_UPDATE")
      assert_equal "1", final_call.fetch("env").fetch("HOMEBREW_NO_INSTALL_CLEANUP")
      assert_equal "1", final_call.fetch("env").fetch("HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK")
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_preflight_blocks_young_dependency_and_does_not_run_final_upgrade
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(
        dir,
        "Formula/o/oldpkg.rb" => 10,
        "Formula/y/youngdep.rb" => 1
      )
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_json(scenario_path, {
        "repos" => { "homebrew/core" => tap_repo },
        "outdated" => {
          "formulae" => [{ "name" => "oldpkg" }],
          "casks" => []
        },
        "formulae" => [
          formula_info("oldpkg", tap: "homebrew/core", path: "Formula/o/oldpkg.rb", head: head),
          formula_info("youngdep", tap: "homebrew/core", path: "Formula/y/youngdep.rb", head: head)
        ],
        "casks" => [],
        "dry_run_output" => "==> Would upgrade 2 outdated packages:\nhomebrew/core/oldpkg 1.0 -> 2.0\nhomebrew/core/youngdep 1.0 -> 2.0\n"
      })

      _stdout, stderr, status = run_bin(
        ["bin/brew", "upgrade"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      refute status.success?
      assert_match(/refusing to upgrade/, stderr)
      calls = read_log(log_path).map { |entry| entry["args"] }
      assert_includes calls, ["upgrade", "--dry-run", "homebrew/core/oldpkg"]
      refute_includes calls, ["upgrade", "homebrew/core/oldpkg"]
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_empty_allowlist_exits_zero_without_upgrade
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(dir, "Formula/y/youngpkg.rb" => 1)
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_json(scenario_path, {
        "repos" => { "homebrew/core" => tap_repo },
        "outdated" => {
          "formulae" => [{ "name" => "youngpkg" }],
          "casks" => []
        },
        "formulae" => [
          formula_info("youngpkg", tap: "homebrew/core", path: "Formula/y/youngpkg.rb", head: head)
        ],
        "casks" => [],
        "dry_run_output" => ""
      })

      stdout, stderr, status = run_bin(
        ["bin/brew", "upgrade"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      assert status.success?, stderr
      assert_match(/no eligible packages/, stdout)
      calls = read_log(log_path).map { |entry| entry["args"] }
      refute calls.any? { |args| args.first == "upgrade" }
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_non_upgrade_execs_real_brew_directly
    Dir.mktmpdir do |dir|
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_json(scenario_path, {
        "repos" => {},
        "outdated" => { "formulae" => [], "casks" => [] },
        "formulae" => [],
        "casks" => [],
        "dry_run_output" => ""
      })

      stdout, stderr, status = run_bin(
        ["bin/brew", "info", "jq"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      assert status.success?, stderr
      assert_match(/"formulae"/, stdout)
      assert_equal [["info", "jq"]], read_log(log_path).map { |entry| entry["args"] }
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_user_dry_run_prints_validated_preflight_and_skips_final_upgrade
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(dir, "Formula/o/oldpkg.rb" => 10)
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: { "homebrew/core" => tap_repo },
        outdated: { "formulae" => [{ "name" => "oldpkg" }], "casks" => [] },
        formulae: [
          formula_info("oldpkg", tap: "homebrew/core", path: "Formula/o/oldpkg.rb", head: head)
        ],
        dry_run_output: "==> Would upgrade 1 outdated package:\nhomebrew/core/oldpkg 1.0 -> 2.0\n"
      )

      stdout, stderr, status = run_bin(
        ["bin/brew", "upgrade", "--dry-run"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      assert status.success?, stderr
      assert_match(/Would upgrade/, stdout)
      calls = read_log(log_path).map { |entry| entry["args"] }
      assert_includes calls, ["upgrade", "--dry-run", "homebrew/core/oldpkg"]
      refute_includes calls, ["upgrade", "homebrew/core/oldpkg"]
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_unknown_flag_fails_before_any_brew_command
    Dir.mktmpdir do |dir|
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: {},
        outdated: { "formulae" => [], "casks" => [] }
      )

      _stdout, stderr, status = run_bin(
        ["bin/brew", "upgrade", "--future-homebrew-flag", "oldpkg"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      refute status.success?
      assert_match(/Unsupported or unsafe/, stderr)
      assert_empty read_log(log_path)
    end
  end

  def test_preflight_unparseable_output_fails_closed_without_final_upgrade
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(dir, "Formula/o/oldpkg.rb" => 10)
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: { "homebrew/core" => tap_repo },
        outdated: { "formulae" => [{ "name" => "oldpkg" }], "casks" => [] },
        formulae: [
          formula_info("oldpkg", tap: "homebrew/core", path: "Formula/o/oldpkg.rb", head: head)
        ],
        dry_run_output: "==> Would upgrade 1 outdated package:\n"
      )

      _stdout, stderr, status = run_bin(
        ["bin/brew", "upgrade"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      refute status.success?
      assert_match(/could not parse any package names/, stderr)
      calls = read_log(log_path).map { |entry| entry["args"] }
      assert_includes calls, ["upgrade", "--dry-run", "homebrew/core/oldpkg"]
      refute_includes calls, ["upgrade", "homebrew/core/oldpkg"]
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_preflight_brew_failure_is_propagated_without_final_upgrade
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(dir, "Formula/o/oldpkg.rb" => 10)
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: { "homebrew/core" => tap_repo },
        outdated: { "formulae" => [{ "name" => "oldpkg" }], "casks" => [] },
        formulae: [
          formula_info("oldpkg", tap: "homebrew/core", path: "Formula/o/oldpkg.rb", head: head)
        ],
        dry_run_output: "preflight failed\n",
        dry_run_status: 42
      )

      stdout, _stderr, status = run_bin(
        ["bin/brew", "upgrade"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      assert_equal 42, status.exitstatus
      assert_match(/preflight failed/, stdout)
      calls = read_log(log_path).map { |entry| entry["args"] }
      assert_includes calls, ["upgrade", "--dry-run", "homebrew/core/oldpkg"]
      refute_includes calls, ["upgrade", "homebrew/core/oldpkg"]
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_plan_command_never_runs_upgrade
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(dir, "Formula/o/oldpkg.rb" => 10)
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: { "homebrew/core" => tap_repo },
        outdated: { "formulae" => [{ "name" => "oldpkg" }], "casks" => [] },
        formulae: [
          formula_info("oldpkg", tap: "homebrew/core", path: "Formula/o/oldpkg.rb", head: head)
        ]
      )

      stdout, stderr, status = run_bin(
        ["bin/homebrew-age-gate", "plan"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      assert status.success?, stderr
      assert_match(/Allowed:/, stdout)
      calls = read_log(log_path).map { |entry| entry["args"] }
      refute calls.any? { |args| args.first == "upgrade" }
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_config_error_aborts_before_any_brew_command
    Dir.mktmpdir do |dir|
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      config_path = File.join(dir, "config.json")
      write_json(config_path, { "min_age_days" => "seven" })
      write_scenario(
        scenario_path,
        repos: {},
        outdated: { "formulae" => [], "casks" => [] }
      )

      _stdout, stderr, status = run_bin(
        ["bin/brew", "upgrade"],
        env: fake_env(
          dir,
          fake_brew,
          scenario_path,
          log_path,
          "HOMEBREW_AGE_GATE_CONFIG" => config_path
        )
      )

      refute status.success?
      assert_match(/min_age_days/, stderr)
      assert_empty read_log(log_path)
    end
  end

  def test_auto_update_cask_allowed_by_config_uses_fake_final_upgrade
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(dir, "Casks/s/slack.rb" => 10)
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      config_path = File.join(dir, "config.json")
      write_json(config_path, {
        "allow_auto_updates_casks" => ["homebrew/cask/slack"]
      })
      write_scenario(
        scenario_path,
        repos: { "homebrew/cask" => tap_repo },
        outdated: { "formulae" => [], "casks" => [{ "name" => "slack" }] },
        casks: [
          cask_info("slack", tap: "homebrew/cask", path: "Casks/s/slack.rb", head: head, auto_updates: true)
        ],
        dry_run_output: "==> Would upgrade 1 outdated package:\nhomebrew/cask/slack 4.0 -> 5.0\n"
      )

      stdout, stderr, status = run_bin(
        ["bin/brew", "upgrade", "--cask"],
        env: fake_env(
          dir,
          fake_brew,
          scenario_path,
          log_path,
          "HOMEBREW_AGE_GATE_CONFIG" => config_path
        )
      )

      assert status.success?, stderr
      assert_match(/homebrew\/cask\/slack/, stdout)
      calls = read_log(log_path).map { |entry| entry["args"] }
      assert_includes calls, ["outdated", "--json=v2", "--cask"]
      assert_includes calls, ["upgrade", "--cask", "--dry-run", "homebrew/cask/slack"]
      assert_includes calls, ["upgrade", "--cask", "homebrew/cask/slack"]
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_doctor_does_not_execute_brew
    Dir.mktmpdir do |dir|
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: {},
        outdated: { "formulae" => [], "casks" => [] }
      )

      stdout, stderr, status = run_bin(
        ["bin/homebrew-age-gate", "doctor"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      assert status.success?, stderr
      assert_match(/doctor ok/, stdout)
      assert_empty read_log(log_path)
    end
  end

  private
end
