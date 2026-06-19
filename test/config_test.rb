# frozen_string_literal: true

require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_defaults
    Dir.mktmpdir do |dir|
      env = { "HOME" => dir }
      config = HomebrewAgeGate::Config.load(env)

      assert_equal 7, config.min_age_days
      assert_equal "/opt/homebrew/bin/brew", config.real_brew_path
      refute config.unsafe_preserve_installed_dependents_check?
    end
  end

  def test_invalid_unknown_key_fails
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.json")
      write_json(path, { "surprise" => true })

      error = assert_raises(HomebrewAgeGate::ConfigError) do
        HomebrewAgeGate::Config.load("HOMEBREW_AGE_GATE_CONFIG" => path)
      end

      assert_match(/Unknown config key/, error.message)
    end
  end

  def test_xdg_config_path_is_used
    Dir.mktmpdir do |dir|
      config_dir = File.join(dir, "xdg", "homebrew-age-gate")
      FileUtils.mkdir_p(config_dir)
      path = File.join(config_dir, "config.json")
      write_json(path, { "min_age_days" => 14 })

      config = HomebrewAgeGate::Config.load("HOME" => dir, "XDG_CONFIG_HOME" => File.join(dir, "xdg"))

      assert_equal path, config.path
      assert_equal 14, config.min_age_days
    end
  end

  def test_project_local_xdg_config_path_falls_back_to_home_config
    Dir.mktmpdir do |dir|
      config = HomebrewAgeGate::Config.load(
        "HOME" => dir,
        "XDG_CONFIG_HOME" => HomebrewAgeGate::HomebrewEnv.default_project_root
      )

      assert_equal File.join(dir, ".config", "homebrew-age-gate", "config.json"), config.path
    end
  end

  def test_env_overrides_real_brew_path
    Dir.mktmpdir do |dir|
      config = HomebrewAgeGate::Config.load(
        "HOME" => dir,
        "HOMEBREW_AGE_GATE_REAL_BREW" => File.join(dir, "fake-brew")
      )

      assert_equal File.join(dir, "fake-brew"), config.real_brew_path
    end
  end

  def test_invalid_min_age_fails
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.json")
      write_json(path, { "min_age_days" => -1 })

      error = assert_raises(HomebrewAgeGate::ConfigError) do
        HomebrewAgeGate::Config.load("HOMEBREW_AGE_GATE_CONFIG" => path)
      end

      assert_match(/min_age_days/, error.message)
    end
  end

  def test_invalid_allowlist_type_fails
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.json")
      write_json(path, { "allow_auto_updates_casks" => "slack" })

      error = assert_raises(HomebrewAgeGate::ConfigError) do
        HomebrewAgeGate::Config.load("HOMEBREW_AGE_GATE_CONFIG" => path)
      end

      assert_match(/allow_auto_updates_casks/, error.message)
    end
  end

  def test_legacy_allow_latest_casks_key_is_accepted_but_ignored
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.json")
      write_json(path, { "allow_latest_casks" => ["homebrew/cask/old-app"] })

      config = HomebrewAgeGate::Config.load("HOMEBREW_AGE_GATE_CONFIG" => path)

      assert_equal 7, config.min_age_days
      refute_includes config.values.keys, "allow_latest_casks"
    end
  end

  def test_name_set_accepts_canonical_and_core_short_names
    package = HomebrewAgeGate::Package.new(
      type: :formula,
      name: "jq",
      tap: "homebrew/core",
      source_path: "Formula/j/jq.rb",
      tap_git_head: "abc",
      version: "1.0",
      auto_updates: false
    )

    assert HomebrewAgeGate::NameSet.new(["jq"]).include_package?(package)
    assert HomebrewAgeGate::NameSet.new(["homebrew/core/jq"]).include_package?(package)
  end
end
