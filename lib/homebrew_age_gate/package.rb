# frozen_string_literal: true

module HomebrewAgeGate
  class Package
    attr_reader :type, :name, :tap, :source_path, :tap_git_head, :version, :auto_updates

    def self.from_formula_info(info)
      new(
        type: :formula,
        name: info.fetch("name"),
        tap: info["tap"],
        source_path: info["ruby_source_path"],
        tap_git_head: info["tap_git_head"],
        version: info.dig("versions", "stable"),
        auto_updates: false
      )
    end

    def self.from_cask_info(info)
      new(
        type: :cask,
        name: info["token"] || info.fetch("full_token"),
        tap: info["tap"],
        source_path: info["ruby_source_path"],
        tap_git_head: info["tap_git_head"],
        version: info["version"],
        auto_updates: info["auto_updates"] == true
      )
    end

    def initialize(type:, name:, tap:, source_path:, tap_git_head:, version:, auto_updates:)
      @type = type
      @name = name
      @tap = tap
      @source_path = source_path
      @tap_git_head = tap_git_head
      @version = version
      @auto_updates = auto_updates
    end

    def formula?
      type == :formula
    end

    def cask?
      type == :cask
    end

    def canonical_name
      return name if tap.nil? || tap.empty?

      "#{tap}/#{name}"
    end

    def latest_cask?
      cask? && version.to_s == "latest"
    end

    def auto_updates_cask?
      cask? && auto_updates
    end
  end
end

