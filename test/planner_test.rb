# frozen_string_literal: true

require_relative "test_helper"

class PlannerTest < Minitest::Test
  def test_blank_upgrade_plans_formulae_only
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(
        dir,
        "Formula/o/oldpkg.rb" => 10,
        "Formula/y/youngpkg.rb" => 1,
        "Casks/s/slack.rb" => 10
      )
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_json(scenario_path, {
        "repos" => { "homebrew/core" => tap_repo, "homebrew/cask" => tap_repo },
        "outdated" => {
          "formulae" => [
            { "name" => "oldpkg" },
            { "name" => "youngpkg" }
          ],
          "casks" => [
            { "name" => "slack" }
          ]
        },
        "formulae" => [
          formula_info("oldpkg", tap: "homebrew/core", path: "Formula/o/oldpkg.rb", head: head),
          formula_info("youngpkg", tap: "homebrew/core", path: "Formula/y/youngpkg.rb", head: head)
        ],
        "casks" => [
          cask_info("slack", tap: "homebrew/cask", path: "Casks/s/slack.rb", head: head, auto_updates: true)
        ],
        "dry_run_output" => ""
      })

      config = HomebrewAgeGate::Config.load(
        "HOME" => dir,
        "HOMEBREW_AGE_GATE_REAL_BREW" => fake_brew
      )
      runner = HomebrewAgeGate::BrewRunner.new(fake_brew)
      planner = HomebrewAgeGate::Planner.new(config: config, runner: runner)

      env = { "FAKE_BREW_SCENARIO" => scenario_path, "FAKE_BREW_LOG" => log_path }
      with_env(env) do
        plan = planner.initial_plan(["upgrade"])
        assert_equal ["homebrew/core/oldpkg"], plan.allowed_packages.map(&:canonical_name)
        assert_equal ["homebrew/core/youngpkg"], plan.skipped.map { |decision| decision.package.canonical_name }
        assert_equal ["too young"], plan.skipped.map(&:reason)
      end

      assert_includes read_log(log_path).map { |entry| entry["args"] }, ["outdated", "--json=v2", "--formula"]
    end
  end

  def test_unknown_age_can_be_allowed_only_by_named_unsafe_config
    Dir.mktmpdir do |dir|
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      config_path = File.join(dir, "config.json")
      write_json(config_path, {
        "unsafe_allow_unknown_age" => ["homebrew/core/missing-history"]
      })
      write_json(scenario_path, {
        "repos" => { "homebrew/core" => dir },
        "outdated" => {
          "formulae" => [{ "name" => "missing-history" }],
          "casks" => []
        },
        "formulae" => [
          formula_info("missing-history", tap: "homebrew/core", path: "Formula/m/missing-history.rb", head: "HEAD")
        ],
        "casks" => [],
        "dry_run_output" => ""
      })

      config = HomebrewAgeGate::Config.load(
        "HOMEBREW_AGE_GATE_CONFIG" => config_path,
        "HOMEBREW_AGE_GATE_REAL_BREW" => fake_brew
      )
      runner = HomebrewAgeGate::BrewRunner.new(fake_brew)
      planner = HomebrewAgeGate::Planner.new(config: config, runner: runner)

      with_env("FAKE_BREW_SCENARIO" => scenario_path, "FAKE_BREW_LOG" => log_path) do
        plan = planner.initial_plan(["upgrade"])
        assert_equal ["homebrew/core/missing-history"], plan.allowed_packages.map(&:canonical_name)
        assert_match(/unknown age allowed/, plan.allowed.first.reason)
      end
    end
  end

  def test_unknown_age_is_skipped_by_default
    Dir.mktmpdir do |dir|
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: { "homebrew/core" => dir },
        outdated: { "formulae" => [{ "name" => "missing-history" }], "casks" => [] },
        formulae: [
          formula_info("missing-history", tap: "homebrew/core", path: "Formula/m/missing-history.rb", head: "HEAD")
        ]
      )

      config = HomebrewAgeGate::Config.load(
        "HOME" => dir,
        "HOMEBREW_AGE_GATE_REAL_BREW" => fake_brew
      )
      runner = HomebrewAgeGate::BrewRunner.new(fake_brew)
      planner = HomebrewAgeGate::Planner.new(config: config, runner: runner)

      with_env("FAKE_BREW_SCENARIO" => scenario_path, "FAKE_BREW_LOG" => log_path) do
        plan = planner.initial_plan(["upgrade"])
        assert_empty plan.allowed
        assert_equal ["homebrew/core/missing-history"], plan.skipped.map { |decision| decision.package.canonical_name }
        assert_match(/unknown age/, plan.skipped.first.reason)
      end
    end
  end

  def test_latest_casks_are_age_gated_and_auto_updates_can_be_allowed_per_cask
    Dir.mktmpdir do |dir|
      tap_repo, head = create_tap_repo(
        dir,
        "Casks/l/latest-old.rb" => 10,
        "Casks/l/latest-young.rb" => 1,
        "Casks/a/auto-app.rb" => 10
      )
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      config_path = File.join(dir, "config.json")
      write_json(config_path, {
        "allow_auto_updates_casks" => ["homebrew/cask/auto-app"]
      })
      write_scenario(
        scenario_path,
        repos: { "homebrew/cask" => tap_repo },
        outdated: {
          "formulae" => [],
          "casks" => [{ "name" => "latest-old" }, { "name" => "latest-young" }, { "name" => "auto-app" }]
        },
        casks: [
          cask_info("latest-old", tap: "homebrew/cask", path: "Casks/l/latest-old.rb", head: head, version: "latest"),
          cask_info("latest-young", tap: "homebrew/cask", path: "Casks/l/latest-young.rb", head: head, version: "latest"),
          cask_info("auto-app", tap: "homebrew/cask", path: "Casks/a/auto-app.rb", head: head, auto_updates: true)
        ]
      )

      config = HomebrewAgeGate::Config.load(
        "HOMEBREW_AGE_GATE_CONFIG" => config_path,
        "HOMEBREW_AGE_GATE_REAL_BREW" => fake_brew
      )
      runner = HomebrewAgeGate::BrewRunner.new(fake_brew)
      planner = HomebrewAgeGate::Planner.new(config: config, runner: runner)

      with_env("FAKE_BREW_SCENARIO" => scenario_path, "FAKE_BREW_LOG" => log_path) do
        plan = planner.initial_plan(["upgrade", "--cask"])
        assert_equal ["homebrew/cask/latest-old", "homebrew/cask/auto-app"], plan.allowed_packages.map(&:canonical_name)
        assert_equal ["homebrew/cask/latest-young"], plan.skipped.map { |decision| decision.package.canonical_name }
        assert_equal ["too young"], plan.skipped.map(&:reason)
      end
    end
  end

  def test_outdated_discovery_receives_explicit_names_and_safe_flags
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

      config = HomebrewAgeGate::Config.load(
        "HOME" => dir,
        "HOMEBREW_AGE_GATE_REAL_BREW" => fake_brew
      )
      runner = HomebrewAgeGate::BrewRunner.new(fake_brew)
      planner = HomebrewAgeGate::Planner.new(config: config, runner: runner)

      with_env("FAKE_BREW_SCENARIO" => scenario_path, "FAKE_BREW_LOG" => log_path) do
        planner.initial_plan(["upgrade", "--formula", "--fetch-HEAD", "oldpkg"])
      end

      assert_includes read_log(log_path).map { |entry| entry["args"] }, ["outdated", "--json=v2", "--formula", "--fetch-HEAD", "oldpkg"]
    end
  end

  def test_final_env_can_unsafely_preserve_installed_dependents_check
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "config.json")
      write_json(config_path, { "unsafe_preserve_installed_dependents_check" => true })
      config = HomebrewAgeGate::Config.load(
        "HOMEBREW_AGE_GATE_CONFIG" => config_path,
        "HOMEBREW_AGE_GATE_REAL_BREW" => File.join(dir, "fake-brew")
      )
      planner = HomebrewAgeGate::Planner.new(
        config: config,
        runner: HomebrewAgeGate::BrewRunner.new(config.real_brew_path)
      )

      assert_equal "1", planner.final_env.fetch("HOMEBREW_NO_AUTO_UPDATE")
      assert_equal "1", planner.final_env.fetch("HOMEBREW_NO_INSTALL_CLEANUP")
      refute_includes planner.final_env.keys, "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"
    end
  end

  private

  def with_env(values)
    old = {}
    values.each do |key, value|
      old[key] = ENV[key]
      ENV[key] = value
    end
    yield
  ensure
    values.each_key do |key|
      if old[key].nil?
        ENV.delete(key)
      else
        ENV[key] = old[key]
      end
    end
  end
end
