# frozen_string_literal: true

module HomebrewAgeGate
  module HomebrewEnv
    KEY = "HOMEBREW_USER_CONFIG_HOME"

    def self.child_env(overrides = {}, process_env: ENV, project_root: default_project_root)
      return overrides.dup if present?(overrides[KEY]) || present?(process_env[KEY])

      config_home = user_config_home(process_env.to_h.merge(overrides), project_root: project_root)
      return overrides.dup unless config_home

      { KEY => config_home }.merge(overrides)
    end

    def self.user_config_home(env = ENV, project_root: default_project_root)
      xdg_config_home = env["XDG_CONFIG_HOME"]
      if present?(xdg_config_home) && !project_local_path?(xdg_config_home, project_root)
        return File.join(xdg_config_home, "homebrew")
      end

      home = env["HOME"]
      return nil unless present?(home)

      File.join(home, ".homebrew")
    end

    def self.project_local_path?(path, project_root = default_project_root)
      expanded_path = File.expand_path(path)
      expanded_root = File.expand_path(project_root)
      expanded_path == expanded_root || expanded_path.start_with?("#{expanded_root}#{File::SEPARATOR}")
    rescue ArgumentError
      false
    end

    def self.display_path(path, env = ENV)
      return "(none)" unless present?(path)

      home = env["HOME"]
      return path unless present?(home)

      expanded_path = File.expand_path(path)
      expanded_home = File.expand_path(home)
      return "$HOME" if expanded_path == expanded_home
      return path unless expanded_path.start_with?("#{expanded_home}#{File::SEPARATOR}")

      "$HOME/#{expanded_path.delete_prefix("#{expanded_home}#{File::SEPARATOR}")}"
    rescue ArgumentError
      path
    end

    def self.default_project_root
      File.expand_path("../..", __dir__)
    end

    def self.present?(value)
      value && !value.empty?
    end
    private_class_method :present?
  end
end
