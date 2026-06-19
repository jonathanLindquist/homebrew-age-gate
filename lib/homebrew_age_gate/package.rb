# frozen_string_literal: true

module HomebrewAgeGate
  class Package
    attr_reader :type,
                :name,
                :tap,
                :source_path,
                :source_checksum,
                :tap_git_head,
                :version,
                :auto_updates,
                :installed_versions

    def self.from_formula_info(info)
      new(
        type: :formula,
        name: info.fetch("name"),
        tap: info["tap"],
        source_path: info["ruby_source_path"],
        source_checksum: info.dig("ruby_source_checksum", "sha256"),
        tap_git_head: info["tap_git_head"],
        version: info.dig("versions", "stable"),
        installed_versions: installed_versions_from_info(info),
        auto_updates: false
      )
    end

    def self.from_cask_info(info)
      new(
        type: :cask,
        name: info["token"] || info.fetch("full_token"),
        tap: info["tap"],
        source_path: info["ruby_source_path"],
        source_checksum: info.dig("ruby_source_checksum", "sha256"),
        tap_git_head: info["tap_git_head"],
        version: info["version"],
        installed_versions: installed_versions_from_info(info),
        auto_updates: info["auto_updates"] == true
      )
    end

    def self.installed_versions_from_info(info)
      installed_version_values(info["installed"])
        .map(&:to_s)
        .reject(&:empty?)
        .uniq
    end

    def self.installed_version_values(value)
      case value
      when Array
        value.flat_map { |entry| installed_version_values(entry) }
      when Hash
        [value["version"]]
      when String
        [value]
      else
        []
      end
    end

    def initialize(type:, name:, tap:, source_path:, tap_git_head:, version:, auto_updates:, source_checksum: nil, installed_versions: [])
      @type = type
      @name = name
      @tap = tap
      @source_path = source_path
      @source_checksum = source_checksum
      @tap_git_head = tap_git_head
      @version = version
      @auto_updates = auto_updates
      @installed_versions = installed_versions
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

    def auto_updates_cask?
      cask? && auto_updates
    end
  end
end
