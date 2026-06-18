# frozen_string_literal: true

require_relative "test_helper"

class AgeResolverTest < Minitest::Test
  def test_uses_committer_date_for_age
    Dir.mktmpdir do |dir|
      repo, head = create_tap_repo(dir, "Formula/o/oldpkg.rb" => 8)
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: { "homebrew/core" => repo },
        outdated: { "formulae" => [], "casks" => [] }
      )
      package = HomebrewAgeGate::Package.new(
        type: :formula,
        name: "oldpkg",
        tap: "homebrew/core",
        source_path: "Formula/o/oldpkg.rb",
        tap_git_head: head,
        version: "2.0.0",
        auto_updates: false
      )

      with_env("FAKE_BREW_SCENARIO" => scenario_path, "FAKE_BREW_LOG" => log_path) do
        resolver = HomebrewAgeGate::AgeResolver.new(
          runner: HomebrewAgeGate::BrewRunner.new(fake_brew),
          now: Time.now
        )
        result = resolver.resolve(package)

        assert result.known?
        assert_operator result.age_seconds, :>=, 7 * 86_400
      end

      assert_no_real_brew_calls!(log_path)
    end
  end

  def test_missing_git_history_is_unknown
    Dir.mktmpdir do |dir|
      repo, head = create_tap_repo(dir, "Formula/o/oldpkg.rb" => 8)
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      write_scenario(
        scenario_path,
        repos: { "homebrew/core" => repo },
        outdated: { "formulae" => [], "casks" => [] }
      )
      package = HomebrewAgeGate::Package.new(
        type: :formula,
        name: "missing",
        tap: "homebrew/core",
        source_path: "Formula/m/missing.rb",
        tap_git_head: head,
        version: "2.0.0",
        auto_updates: false
      )

      with_env("FAKE_BREW_SCENARIO" => scenario_path, "FAKE_BREW_LOG" => log_path) do
        resolver = HomebrewAgeGate::AgeResolver.new(runner: HomebrewAgeGate::BrewRunner.new(fake_brew))
        result = resolver.resolve(package)

        refute result.known?
        assert_match(/no git history/, result.reason)
      end

      assert_no_real_brew_calls!(log_path)
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

