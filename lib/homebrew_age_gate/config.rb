# frozen_string_literal: true

require "json"
require "set"

module HomebrewAgeGate
  class ConfigError < StandardError; end

  class Config
    DEFAULT_REAL_BREW = "/opt/homebrew/bin/brew"
    DEFAULTS = {
      "min_age_days" => 7,
      "real_brew_path" => DEFAULT_REAL_BREW,
      "allow_auto_updates_casks" => [],
      "allow_latest_casks" => [],
      "unsafe_allow_unknown_age" => [],
      "unsafe_preserve_installed_dependents_check" => false
    }.freeze

    KEYS = DEFAULTS.keys.freeze

    attr_reader :path, :values

    def self.load(env = ENV)
      path = env["HOMEBREW_AGE_GATE_CONFIG"] || default_path(env)
      raw_values = {}

      if path && File.exist?(path)
        begin
          parsed = JSON.parse(File.read(path))
        rescue JSON::ParserError => e
          raise ConfigError, "Invalid JSON in #{path}: #{e.message}"
        end
        raise ConfigError, "Config root must be a JSON object" unless parsed.is_a?(Hash)

        unknown_keys = parsed.keys - KEYS
        unless unknown_keys.empty?
          raise ConfigError, "Unknown config key(s): #{unknown_keys.sort.join(", ")}"
        end

        raw_values = parsed
      end

      values = DEFAULTS.merge(raw_values)
      values["real_brew_path"] = env["HOMEBREW_AGE_GATE_REAL_BREW"] if env["HOMEBREW_AGE_GATE_REAL_BREW"]
      new(path, values)
    end

    def self.default_path(env)
      home = env["HOME"]
      xdg = env["XDG_CONFIG_HOME"]
      return File.join(xdg, "homebrew-age-gate", "config.json") if xdg && !xdg.empty?
      return nil unless home && !home.empty?

      File.join(home, ".config", "homebrew-age-gate", "config.json")
    end

    def initialize(path, values)
      @path = path
      @values = values
      validate!
    end

    def min_age_days
      values.fetch("min_age_days")
    end

    def real_brew_path
      values.fetch("real_brew_path")
    end

    def unsafe_preserve_installed_dependents_check?
      values.fetch("unsafe_preserve_installed_dependents_check")
    end

    def allow_auto_updates_cask?(package)
      name_set("allow_auto_updates_casks").include_package?(package)
    end

    def allow_latest_cask?(package)
      name_set("allow_latest_casks").include_package?(package)
    end

    def unsafe_allow_unknown_age?(package)
      name_set("unsafe_allow_unknown_age").include_package?(package)
    end

    private

    def validate!
      unless min_age_days.is_a?(Integer) && min_age_days >= 0
        raise ConfigError, "min_age_days must be a non-negative integer"
      end

      unless real_brew_path.is_a?(String) && !real_brew_path.empty?
        raise ConfigError, "real_brew_path must be a non-empty string"
      end

      %w[allow_auto_updates_casks allow_latest_casks unsafe_allow_unknown_age].each do |key|
        value = values.fetch(key)
        unless value.is_a?(Array) && value.all? { |entry| entry.is_a?(String) && !entry.empty? }
          raise ConfigError, "#{key} must be an array of non-empty strings"
        end
      end

      unless [true, false].include?(unsafe_preserve_installed_dependents_check?)
        raise ConfigError, "unsafe_preserve_installed_dependents_check must be true or false"
      end
    end

    def name_set(key)
      NameSet.new(values.fetch(key))
    end
  end

  class NameSet
    def initialize(names)
      @names = names.to_set
    end

    def include_package?(package)
      return true if @names.include?(package.canonical_name)

      if package.formula? && package.tap == "homebrew/core"
        return true if @names.include?(package.name)
      end

      if package.cask? && package.tap == "homebrew/cask"
        return true if @names.include?(package.name)
      end

      false
    end
  end
end

