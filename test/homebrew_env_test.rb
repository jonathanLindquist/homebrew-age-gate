# frozen_string_literal: true

require_relative "test_helper"

class HomebrewEnvTest < Minitest::Test
  def test_uses_xdg_homebrew_config_when_xdg_is_not_project_local
    Dir.mktmpdir do |dir|
      project_root = File.join(dir, "repo")
      xdg_config_home = File.join(dir, "config")
      env = { "HOME" => File.join(dir, "home"), "XDG_CONFIG_HOME" => xdg_config_home }

      assert_equal(
        File.join(xdg_config_home, "homebrew"),
        HomebrewAgeGate::HomebrewEnv.user_config_home(env, project_root: project_root)
      )
    end
  end

  def test_uses_home_homebrew_config_when_xdg_is_project_root
    Dir.mktmpdir do |dir|
      project_root = File.join(dir, "repo")
      home = File.join(dir, "home")
      env = { "HOME" => home, "XDG_CONFIG_HOME" => project_root }

      assert_equal(
        File.join(home, ".homebrew"),
        HomebrewAgeGate::HomebrewEnv.user_config_home(env, project_root: project_root)
      )
    end
  end

  def test_uses_home_homebrew_config_when_xdg_is_inside_project_root
    Dir.mktmpdir do |dir|
      project_root = File.join(dir, "repo")
      home = File.join(dir, "home")
      env = { "HOME" => home, "XDG_CONFIG_HOME" => File.join(project_root, "tmp-config") }

      assert_equal(
        File.join(home, ".homebrew"),
        HomebrewAgeGate::HomebrewEnv.user_config_home(env, project_root: project_root)
      )
    end
  end

  def test_child_env_preserves_explicit_homebrew_user_config_home
    Dir.mktmpdir do |dir|
      project_root = File.join(dir, "repo")
      explicit = File.join(dir, "homebrew-config")
      process_env = {
        "HOME" => File.join(dir, "home"),
        "XDG_CONFIG_HOME" => project_root,
        "HOMEBREW_USER_CONFIG_HOME" => explicit
      }

      assert_equal(
        { "HOMEBREW_NO_AUTO_UPDATE" => "1" },
        HomebrewAgeGate::HomebrewEnv.child_env(
          { "HOMEBREW_NO_AUTO_UPDATE" => "1" },
          process_env: process_env,
          project_root: project_root
        )
      )
    end
  end

  def test_child_env_adds_homebrew_user_config_home_without_unsetting_xdg
    Dir.mktmpdir do |dir|
      project_root = File.join(dir, "repo")
      home = File.join(dir, "home")
      process_env = { "HOME" => home, "XDG_CONFIG_HOME" => project_root }

      child_env = HomebrewAgeGate::HomebrewEnv.child_env(
        { "HOMEBREW_NO_AUTO_UPDATE" => "1" },
        process_env: process_env,
        project_root: project_root
      )

      assert_equal File.join(home, ".homebrew"), child_env.fetch("HOMEBREW_USER_CONFIG_HOME")
      assert_equal "1", child_env.fetch("HOMEBREW_NO_AUTO_UPDATE")
      refute_includes child_env.keys, "XDG_CONFIG_HOME"
    end
  end

  def test_display_path_replaces_home_prefix
    Dir.mktmpdir do |dir|
      home = File.join(dir, "home")
      env = { "HOME" => home }

      assert_equal "$HOME/.homebrew", HomebrewAgeGate::HomebrewEnv.display_path(File.join(home, ".homebrew"), env)
      assert_equal "/opt/homebrew/bin/brew", HomebrewAgeGate::HomebrewEnv.display_path("/opt/homebrew/bin/brew", env)
    end
  end
end
