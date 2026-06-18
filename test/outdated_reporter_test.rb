# frozen_string_literal: true

require_relative "test_helper"

class OutdatedReporterTest < Minitest::Test
  def test_annotates_outdated_lines_with_colored_latest_version_dates
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
      write_scenario(
        scenario_path,
        repos: { "homebrew/core" => tap_repo },
        outdated: { "formulae" => [{ "name" => "oldpkg" }, { "name" => "youngpkg" }], "casks" => [] },
        formulae: [
          formula_info("oldpkg", tap: "homebrew/core", path: "Formula/o/oldpkg.rb", head: head),
          formula_info("youngpkg", tap: "homebrew/core", path: "Formula/y/youngpkg.rb", head: head)
        ]
      )
      config = HomebrewAgeGate::Config.load(
        "HOME" => dir,
        "HOMEBREW_AGE_GATE_REAL_BREW" => fake_brew
      )
      reporter = HomebrewAgeGate::OutdatedReporter.new(
        config: config,
        runner: HomebrewAgeGate::BrewRunner.new(fake_brew),
        now: now
      )

      with_env("FAKE_BREW_SCENARIO" => scenario_path, "FAKE_BREW_LOG" => log_path) do
        output = reporter.annotate("oldpkg 1.0 < 2.0\nyoungpkg 1.0 < 2.0\n", color: true)

        assert_includes output, "\e[38;2;119;221;119moldpkg\e[0m \e[38;2;119;221;119mversion:\e[0m 2.0.0 \e[38;2;119;221;119mage:\e[0m 10d"
        assert_includes output, "\e[38;2;255;154;162myoungpkg\e[0m \e[38;2;255;154;162mversion:\e[0m 2.0.0 \e[38;2;255;154;162mage:\e[0m 1d"
        refute_includes output, "\e[38;2;119;221;119m2.0.0"
        refute_includes output, "date:"
      end
    end
  end

  def test_annotates_cask_with_semantic_version_only
    Dir.mktmpdir do |dir|
      now = Time.utc(2026, 6, 18, 12, 0, 0)
      tap_repo, head = create_tap_repo_at(dir, now, "Casks/e/evernote.rb" => 54)
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: { "homebrew/cask" => tap_repo },
        outdated: { "formulae" => [], "casks" => [{ "name" => "evernote" }] },
        casks: [
          cask_info(
            "evernote",
            tap: "homebrew/cask",
            path: "Casks/e/evernote.rb",
            head: head,
            version: "10.105.4,20240910164757,a2e60a8d876a07eded5d212fa56ba45214114ad0"
          )
        ]
      )
      config = HomebrewAgeGate::Config.load(
        "HOME" => dir,
        "HOMEBREW_AGE_GATE_REAL_BREW" => fake_brew
      )
      reporter = HomebrewAgeGate::OutdatedReporter.new(
        config: config,
        runner: HomebrewAgeGate::BrewRunner.new(fake_brew),
        now: now
      )

      with_env("FAKE_BREW_SCENARIO" => scenario_path, "FAKE_BREW_LOG" => log_path) do
        output = reporter.annotate("evernote\n")

        assert_includes output, "evernote version: 10.105.4 age: 54d"
        refute_includes output, "date:"
        refute_includes output, "20240910164757"
        refute_includes output, "a2e60a8d876a07eded5d212fa56ba45214114ad0"
      end
    end
  end

  def test_annotates_too_young_package_with_latest_safe_version
    Dir.mktmpdir do |dir|
      now = Time.utc(2026, 6, 18, 12, 0, 0)
      tap_repo, head = create_tap_repo_history_at(
        dir,
        now,
        "Casks/a/apidog.rb",
        [
          [20, "cask \"apidog\" do\n  version \"2.8.20,oldhash\"\nend\n"],
          [5, "cask \"apidog\" do\n  version \"2.8.34,newhash\"\nend\n"]
        ]
      )
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: { "homebrew/cask" => tap_repo },
        outdated: { "formulae" => [], "casks" => [{ "name" => "apidog" }] },
        casks: [
          cask_info(
            "apidog",
            tap: "homebrew/cask",
            path: "Casks/a/apidog.rb",
            head: head,
            version: "2.8.34,newhash"
          )
        ]
      )
      config = HomebrewAgeGate::Config.load(
        "HOME" => dir,
        "HOMEBREW_AGE_GATE_REAL_BREW" => fake_brew
      )
      reporter = HomebrewAgeGate::OutdatedReporter.new(
        config: config,
        runner: HomebrewAgeGate::BrewRunner.new(fake_brew),
        now: now
      )

      with_env("FAKE_BREW_SCENARIO" => scenario_path, "FAKE_BREW_LOG" => log_path) do
        output = reporter.annotate("apidog\n", color: true)

        assert_includes(
          output,
          "\e[38;2;255;154;162mapidog\e[0m " \
            "\e[38;2;255;154;162mversion:\e[0m 2.8.34 " \
            "\e[38;2;255;154;162mage:\e[0m 5d -> " \
            "\e[38;2;119;221;119mversion:\e[0m 2.8.20 " \
            "\e[38;2;119;221;119mage:\e[0m 20d"
        )
        refute_includes output, "newhash"
        refute_includes output, "oldhash"
      end
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
      old[key].nil? ? ENV.delete(key) : ENV[key] = old[key]
    end
  end
end
