# frozen_string_literal: true

require_relative "test_helper"

class SafeVersionResolverTest < Minitest::Test
  def test_resolves_safe_version_from_explicit_version
    safe_version = resolve_safe_version_from_history(
      "Casks/a/apidog.rb",
      [
        [20, "cask \"apidog\" do\n  version \"2.8.20,oldhash\"\nend\n"],
        [5, "cask \"apidog\" do\n  version \"2.8.34,newhash\"\nend\n"]
      ],
      package_type: :cask,
      package_name: "apidog",
      current_version: "2.8.34,newhash"
    )

    assert_equal "2.8.20", safe_version.version
    assert_equal 20 * 86_400, safe_version.age_seconds
  end

  def test_resolves_safe_formula_version_from_url
    safe_version = resolve_safe_version_from_history(
      "Formula/f/foo.rb",
      [
        [20, "class Foo < Formula\n  url \"https://example.com/releases/foo-1.2.3.tar.gz\"\nend\n"],
        [5, "class Foo < Formula\n  url \"https://example.com/releases/foo-1.3.0.tar.gz\"\nend\n"]
      ],
      package_type: :formula,
      package_name: "foo",
      current_version: "1.3.0"
    )

    assert_equal "1.2.3", safe_version.version
  end

  def test_resolves_safe_formula_version_from_tag_when_url_has_no_version
    safe_version = resolve_safe_version_from_history(
      "Formula/b/bar.rb",
      [
        [20, "class Bar < Formula\n  url \"https://github.com/acme/bar.git\", tag: \"v4.5.6\", revision: \"abcdef\"\nend\n"],
        [5, "class Bar < Formula\n  url \"https://github.com/acme/bar.git\", tag: \"v4.6.0\", revision: \"123456\"\nend\n"]
      ],
      package_type: :formula,
      package_name: "bar",
      current_version: "4.6.0"
    )

    assert_equal "4.5.6", safe_version.version
  end

  def test_omits_safe_version_when_history_has_no_semantic_version
    safe_version = resolve_safe_version_from_history(
      "Formula/n/nope.rb",
      [
        [20, "class Nope < Formula\n  url \"https://github.com/acme/nope.git\", revision: \"abcdef\"\nend\n"],
        [5, "class Nope < Formula\n  url \"https://github.com/acme/nope.git\", revision: \"123456\"\nend\n"]
      ],
      package_type: :formula,
      package_name: "nope",
      current_version: "1.0.0"
    )

    assert_nil safe_version
  end

  def test_omits_safe_version_when_only_version_scheme_is_available
    safe_version = resolve_safe_version_from_history(
      "Formula/s/scheme_only.rb",
      [
        [20, "class SchemeOnly < Formula\n  url \"https://github.com/acme/scheme-only.git\"\n  version_scheme 1\nend\n"],
        [5, "class SchemeOnly < Formula\n  url \"https://github.com/acme/scheme-only.git\"\n  version_scheme 2\nend\n"]
      ],
      package_type: :formula,
      package_name: "scheme-only",
      current_version: "1.0.0"
    )

    assert_nil safe_version
  end

  private

  def resolve_safe_version_from_history(path, commits, package_type:, package_name:, current_version:)
    Dir.mktmpdir do |dir|
      now = Time.utc(2026, 6, 18, 12, 0, 0)
      tap_repo, head = create_tap_repo_history_at(dir, now, path, commits)
      fake_brew = make_fake_brew(dir)
      log_path = File.join(dir, "brew.log")
      scenario_path = File.join(dir, "scenario.json")
      tap = package_type == :formula ? "homebrew/core" : "homebrew/cask"
      write_scenario(
        scenario_path,
        repos: { tap => tap_repo },
        outdated: { "formulae" => [], "casks" => [] }
      )
      package = HomebrewAgeGate::Package.new(
        type: package_type,
        name: package_name,
        tap: tap,
        source_path: path,
        tap_git_head: head,
        version: current_version,
        auto_updates: false
      )
      current_age = HomebrewAgeGate::AgeResult.new(
        known: true,
        commit_time: now - (5 * 86_400),
        age_seconds: 5 * 86_400,
        reason: nil
      )

      with_env("FAKE_BREW_SCENARIO" => scenario_path, "FAKE_BREW_LOG" => log_path) do
        resolver = HomebrewAgeGate::SafeVersionResolver.new(
          runner: HomebrewAgeGate::BrewRunner.new(fake_brew),
          now: now,
          min_age_days: 7
        )
        resolver.resolve(package, current_age)
      end
    end
  end

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
