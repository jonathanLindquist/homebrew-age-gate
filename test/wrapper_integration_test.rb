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
      expected_date = `git -C #{tap_repo.shellescape} log -1 --format=%cs #{head.shellescape} -- Formula/o/oldpkg.rb`.strip
      assert_match(/homebrew\/core\/oldpkg age=\d+\.\d{2}d definition_commit_date=#{expected_date} reason=old enough/, stdout)

      calls = read_log(log_path)
      assert_includes calls.map { |entry| entry["args"] }, ["outdated", "--json=v2", "--formula"]
      assert_includes calls.map { |entry| entry["args"] }, ["upgrade", "--formula", "--dry-run", "homebrew/core/oldpkg"]
      assert_includes calls.map { |entry| entry["args"] }, ["upgrade", "--formula", "homebrew/core/oldpkg"]
      refute_includes calls.map { |entry| entry["args"] }, ["upgrade"]

      final_call = calls.find { |entry| entry["args"] == ["upgrade", "--formula", "homebrew/core/oldpkg"] }
      assert_equal "1", final_call.fetch("env").fetch("HOMEBREW_NO_AUTO_UPDATE")
      assert_equal "1", final_call.fetch("env").fetch("HOMEBREW_NO_INSTALL_CLEANUP")
      assert_equal "1", final_call.fetch("env").fetch("HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK")
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_preflight_defers_root_with_young_dependency_and_exits_zero_without_final_upgrade
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

      stdout, stderr, status = run_bin(
        ["bin/brew", "upgrade"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      assert status.success?, stderr
      assert_match(/Deferred by dependency preflight:/, stdout)
      assert_match(%r{homebrew/core/oldpkg blocked because dry-run includes blocked packages: homebrew/core/youngdep \(too new\)}, stdout)
      assert_match(/no safely upgradeable packages after dependency preflight/, stdout)
      calls = read_log(log_path).map { |entry| entry["args"] }
      assert_includes calls, ["upgrade", "--formula", "--dry-run", "homebrew/core/oldpkg"]
      refute_includes calls, ["upgrade", "--formula", "homebrew/core/oldpkg"]
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_preflight_salvages_green_formulae_not_blocked_by_young_dependencies
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(
        dir,
        "Formula/s/safe-root.rb" => 10,
        "Formula/b/blocked-root.rb" => 10,
        "Formula/y/youngdep.rb" => 1
      )
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: { "homebrew/core" => tap_repo },
        outdated: {
          "formulae" => [{ "name" => "safe-root" }, { "name" => "blocked-root" }],
          "casks" => []
        },
        formulae: [
          formula_info("safe-root", tap: "homebrew/core", path: "Formula/s/safe-root.rb", head: head),
          formula_info("blocked-root", tap: "homebrew/core", path: "Formula/b/blocked-root.rb", head: head),
          formula_info("youngdep", tap: "homebrew/core", path: "Formula/y/youngdep.rb", head: head)
        ],
        dry_run_outputs: {
          "upgrade --formula --dry-run homebrew/core/safe-root homebrew/core/blocked-root" => "==> Would upgrade 3 outdated packages:\nhomebrew/core/safe-root 1.0 -> 2.0\nhomebrew/core/blocked-root 1.0 -> 2.0\nhomebrew/core/youngdep 1.0 -> 2.0\n",
          "upgrade --formula --dry-run homebrew/core/safe-root" => "==> Would upgrade 1 outdated package:\nhomebrew/core/safe-root 1.0 -> 2.0\n",
          "upgrade --formula --dry-run homebrew/core/blocked-root" => "==> Would upgrade 2 outdated packages:\nhomebrew/core/blocked-root 1.0 -> 2.0\nhomebrew/core/youngdep 1.0 -> 2.0\n"
        }
      )

      stdout, stderr, status = run_bin(
        ["bin/brew", "upgrade"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      assert status.success?, stderr
      assert_match(%r{homebrew/core/blocked-root blocked because dry-run includes blocked packages: homebrew/core/youngdep \(too new\)}, stdout)
      calls = read_log(log_path).map { |entry| entry["args"] }
      assert_includes calls, ["upgrade", "--formula", "--dry-run", "homebrew/core/safe-root", "homebrew/core/blocked-root"]
      assert_includes calls, ["upgrade", "--formula", "--dry-run", "homebrew/core/safe-root"]
      assert_includes calls, ["upgrade", "--formula", "--dry-run", "homebrew/core/blocked-root"]
      assert_includes calls, ["upgrade", "--formula", "homebrew/core/safe-root"]
      refute_includes calls, ["upgrade", "--formula", "homebrew/core/blocked-root"]
      refute calls.any? { |args| args.first == "upgrade" && !args.include?("--dry-run") && args.include?("homebrew/core/youngdep") }
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_preflight_unknown_dependency_age_still_fails_closed
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(dir, "Formula/o/oldpkg.rb" => 10)
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: { "homebrew/core" => tap_repo },
        outdated: {
          "formulae" => [{ "name" => "oldpkg" }],
          "casks" => []
        },
        formulae: [
          formula_info("oldpkg", tap: "homebrew/core", path: "Formula/o/oldpkg.rb", head: head),
          formula_info("missingdep", tap: "homebrew/core", path: "Formula/m/missingdep.rb", head: head)
        ],
        dry_run_output: "==> Would upgrade 2 outdated packages:\nhomebrew/core/oldpkg 1.0 -> 2.0\nhomebrew/core/missingdep 1.0 -> 2.0\n"
      )

      _stdout, stderr, status = run_bin(
        ["bin/brew", "upgrade"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      refute status.success?
      assert_match(/refusing to upgrade/, stderr)
      assert_match(/homebrew\/core\/missingdep age=unknown/, stderr)
      calls = read_log(log_path).map { |entry| entry["args"] }
      assert_includes calls, ["upgrade", "--formula", "--dry-run", "homebrew/core/oldpkg"]
      refute_includes calls, ["upgrade", "--formula", "homebrew/core/oldpkg"]
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_blank_upgrade_updates_green_formulae_but_ignores_casks
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(
        dir,
        "Formula/o/oldpkg.rb" => 10,
        "Formula/y/youngpkg.rb" => 1,
        "Casks/o/oldapp.rb" => 10,
        "Casks/y/youngapp.rb" => 1
      )
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: { "homebrew/core" => tap_repo, "homebrew/cask" => tap_repo },
        outdated: {
          "formulae" => [{ "name" => "oldpkg" }, { "name" => "youngpkg" }],
          "casks" => [{ "name" => "oldapp" }, { "name" => "youngapp" }]
        },
        formulae: [
          formula_info("oldpkg", tap: "homebrew/core", path: "Formula/o/oldpkg.rb", head: head),
          formula_info("youngpkg", tap: "homebrew/core", path: "Formula/y/youngpkg.rb", head: head)
        ],
        casks: [
          cask_info("oldapp", tap: "homebrew/cask", path: "Casks/o/oldapp.rb", head: head),
          cask_info("youngapp", tap: "homebrew/cask", path: "Casks/y/youngapp.rb", head: head)
        ],
        dry_run_outputs: {
          "upgrade --formula --dry-run homebrew/core/oldpkg" => "==> Would upgrade 1 outdated package:\nhomebrew/core/oldpkg 1.0 -> 2.0\n",
          "upgrade --cask --dry-run homebrew/cask/oldapp" => "==> Would upgrade 1 outdated package:\nhomebrew/cask/oldapp 1.0 -> 2.0\n"
        }
      )

      stdout, stderr, status = run_bin(
        ["bin/brew", "upgrade"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      assert status.success?, stderr
      assert_match(/homebrew\/core\/oldpkg/, stdout)
      assert_match(/homebrew\/core\/youngpkg/, stdout)
      refute_match(/homebrew\/cask\/oldapp/, stdout)
      refute_match(/homebrew\/cask\/youngapp/, stdout)

      calls = read_log(log_path).map { |entry| entry["args"] }
      assert_includes calls, ["outdated", "--json=v2", "--formula"]
      assert_includes calls, ["upgrade", "--formula", "--dry-run", "homebrew/core/oldpkg"]
      assert_includes calls, ["upgrade", "--formula", "homebrew/core/oldpkg"]

      upgrade_calls = calls.select { |args| args.first == "upgrade" && !args.include?("--dry-run") }
      refute upgrade_calls.any? { |args| args.include?("homebrew/core/youngpkg") }
      refute calls.any? { |args| args.first == "upgrade" && args.include?("--cask") }
      refute calls.any? { |args| args.include?("homebrew/cask/oldapp") }
      refute upgrade_calls.any? { |args| args.include?("homebrew/cask/youngapp") }
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

  def test_outdated_prints_age_gate_dates_with_color
    Dir.mktmpdir do |dir|
      now = Time.utc(2026, 6, 18, 12, 0, 0)
      tap_repo, head = create_tap_repo_at(
        dir,
        now,
        "Formula/o/oldpkg.rb" => 10,
        "Formula/y/youngpkg.rb" => 1
      )
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_json(scenario_path, {
        "repos" => { "homebrew/core" => tap_repo },
        "outdated" => {
          "formulae" => [{ "name" => "oldpkg" }, { "name" => "youngpkg" }],
          "casks" => []
        },
        "outdated_text" => "oldpkg 1.0 < 2.0\nyoungpkg 1.0 < 2.0\n",
        "formulae" => [
          formula_info("oldpkg", tap: "homebrew/core", path: "Formula/o/oldpkg.rb", head: head),
          formula_info("youngpkg", tap: "homebrew/core", path: "Formula/y/youngpkg.rb", head: head)
        ],
        "casks" => [],
        "dry_run_output" => ""
      })

      stdout, stderr, status = run_bin(
        ["bin/brew", "outdated"],
        env: fake_env(
          dir,
          fake_brew,
          scenario_path,
          log_path,
          "HOMEBREW_AGE_GATE_COLOR" => "always"
        )
      )

      assert status.success?, stderr
      assert_includes stdout, "\e[38;2;255;190;120mcurrent version\e[0m"
      assert_includes stdout, "\e[38;2;255;190;120mlatest version\e[0m"
      assert_match(/\e\[38;2;119;221;119moldpkg\e\[0m\s+\| 1\.0\s+\| 2\.0\.0\s+\| \d+d/, stdout)
      assert_match(/\e\[38;2;255;154;162myoungpkg\e\[0m \| 1\.0\s+\| 2\.0\.0\s+\| \d+d/, stdout)
      refute_includes stdout, "\e[38;2;119;221;119m2.0.0"
      refute_includes stdout, "\e[38;2;255;190;120m2.0.0"
      refute_includes stdout, "date:"
      calls = read_log(log_path).map { |entry| entry["args"] }
      assert_includes calls, ["outdated"]
      assert_includes calls, ["info", "--json=v2", "oldpkg", "youngpkg"]
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_outdated_json_passes_through_without_annotations
    Dir.mktmpdir do |dir|
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: {},
        outdated: { "formulae" => [{ "name" => "oldpkg" }], "casks" => [] }
      )

      stdout, stderr, status = run_bin(
        ["bin/brew", "outdated", "--json=v2"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      assert status.success?, stderr
      refute_includes stdout, "date:"
      assert_equal({ "formulae" => [{ "name" => "oldpkg" }], "casks" => [] }, JSON.parse(stdout))
      assert_equal [["outdated", "--json=v2"]], read_log(log_path).map { |entry| entry["args"] }
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_outdated_annotates_stdout_when_brew_returns_nonzero
    Dir.mktmpdir do |dir|
      now = Time.utc(2026, 6, 18, 12, 0, 0)
      tap_repo, head = create_tap_repo_at(dir, now, "Formula/o/oldpkg.rb" => 10)
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_json(scenario_path, {
        "repos" => { "homebrew/core" => tap_repo },
        "outdated" => { "formulae" => [{ "name" => "oldpkg" }], "casks" => [] },
        "outdated_text" => "oldpkg 1.0 < 2.0\n",
        "outdated_status" => 1,
        "formulae" => [
          formula_info("oldpkg", tap: "homebrew/core", path: "Formula/o/oldpkg.rb", head: head)
        ],
        "casks" => [],
        "dry_run_output" => ""
      })

      stdout, stderr, status = run_bin(
        ["bin/brew", "outdated", "oldpkg"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      refute status.success?, stderr
      assert_includes stdout, "name   | current version | latest version | age\n"
      assert_match(/oldpkg \| 1\.0\s+\| 2\.0\.0\s+\| \d+d/, stdout)
      refute_includes stdout, "date:"
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
      assert_includes calls, ["upgrade", "--formula", "--dry-run", "homebrew/core/oldpkg"]
      refute_includes calls, ["upgrade", "--formula", "homebrew/core/oldpkg"]
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_user_dry_run_reports_deferred_formulae_blocked_by_young_dependencies
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(
        dir,
        "Formula/s/safe-root.rb" => 10,
        "Formula/b/blocked-root.rb" => 10,
        "Formula/y/youngdep.rb" => 1
      )
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: { "homebrew/core" => tap_repo },
        outdated: {
          "formulae" => [{ "name" => "safe-root" }, { "name" => "blocked-root" }],
          "casks" => []
        },
        formulae: [
          formula_info("safe-root", tap: "homebrew/core", path: "Formula/s/safe-root.rb", head: head),
          formula_info("blocked-root", tap: "homebrew/core", path: "Formula/b/blocked-root.rb", head: head),
          formula_info("youngdep", tap: "homebrew/core", path: "Formula/y/youngdep.rb", head: head)
        ],
        dry_run_outputs: {
          "upgrade --formula --dry-run homebrew/core/safe-root homebrew/core/blocked-root" => "==> Would upgrade 3 outdated packages:\nhomebrew/core/safe-root 1.0 -> 2.0\nhomebrew/core/blocked-root 1.0 -> 2.0\nhomebrew/core/youngdep 1.0 -> 2.0\n",
          "upgrade --formula --dry-run homebrew/core/safe-root" => "==> Would upgrade 1 outdated package:\nhomebrew/core/safe-root 1.0 -> 2.0\n",
          "upgrade --formula --dry-run homebrew/core/blocked-root" => "==> Would upgrade 2 outdated packages:\nhomebrew/core/blocked-root 1.0 -> 2.0\nhomebrew/core/youngdep 1.0 -> 2.0\n"
        }
      )

      stdout, stderr, status = run_bin(
        ["bin/brew", "upgrade", "--dry-run"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      assert status.success?, stderr
      assert_match(/Would upgrade 1 outdated package:/, stdout)
      assert_match(%r{homebrew/core/safe-root 1\.0 -> 2\.0}, stdout)
      assert_match(%r{homebrew/core/blocked-root blocked because dry-run includes blocked packages: homebrew/core/youngdep \(too new\)}, stdout)
      calls = read_log(log_path).map { |entry| entry["args"] }
      assert_includes calls, ["upgrade", "--formula", "--dry-run", "homebrew/core/safe-root"]
      refute_includes calls, ["upgrade", "--formula", "homebrew/core/safe-root"]
      refute calls.any? { |args| args.first == "upgrade" && !args.include?("--dry-run") }
      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_preflight_falls_back_to_single_root_final_upgrades_when_recombined_batch_is_blocked
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(
        dir,
        "Formula/l/left-root.rb" => 10,
        "Formula/r/right-root.rb" => 10,
        "Formula/y/youngdep.rb" => 1
      )
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: { "homebrew/core" => tap_repo },
        outdated: {
          "formulae" => [{ "name" => "left-root" }, { "name" => "right-root" }],
          "casks" => []
        },
        formulae: [
          formula_info("left-root", tap: "homebrew/core", path: "Formula/l/left-root.rb", head: head),
          formula_info("right-root", tap: "homebrew/core", path: "Formula/r/right-root.rb", head: head),
          formula_info("youngdep", tap: "homebrew/core", path: "Formula/y/youngdep.rb", head: head)
        ],
        dry_run_outputs: {
          "upgrade --formula --dry-run homebrew/core/left-root homebrew/core/right-root" => "==> Would upgrade 3 outdated packages:\nhomebrew/core/left-root 1.0 -> 2.0\nhomebrew/core/right-root 1.0 -> 2.0\nhomebrew/core/youngdep 1.0 -> 2.0\n",
          "upgrade --formula --dry-run homebrew/core/left-root" => "==> Would upgrade 1 outdated package:\nhomebrew/core/left-root 1.0 -> 2.0\n",
          "upgrade --formula --dry-run homebrew/core/right-root" => "==> Would upgrade 1 outdated package:\nhomebrew/core/right-root 1.0 -> 2.0\n"
        }
      )

      _stdout, stderr, status = run_bin(
        ["bin/brew", "upgrade"],
        env: fake_env(dir, fake_brew, scenario_path, log_path)
      )

      assert status.success?, stderr
      calls = read_log(log_path).map { |entry| entry["args"] }
      assert_includes calls, ["upgrade", "--formula", "--dry-run", "homebrew/core/left-root", "homebrew/core/right-root"]
      assert_includes calls, ["upgrade", "--formula", "--dry-run", "homebrew/core/left-root"]
      assert_includes calls, ["upgrade", "--formula", "--dry-run", "homebrew/core/right-root"]
      assert_includes calls, ["upgrade", "--formula", "homebrew/core/left-root"]
      assert_includes calls, ["upgrade", "--formula", "homebrew/core/right-root"]
      refute calls.any? { |args| args.first == "upgrade" && !args.include?("--dry-run") && args.include?("homebrew/core/youngdep") }
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
      assert_includes calls, ["upgrade", "--formula", "--dry-run", "homebrew/core/oldpkg"]
      refute_includes calls, ["upgrade", "--formula", "homebrew/core/oldpkg"]
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
      assert_includes calls, ["upgrade", "--formula", "--dry-run", "homebrew/core/oldpkg"]
      refute_includes calls, ["upgrade", "--formula", "homebrew/core/oldpkg"]
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
