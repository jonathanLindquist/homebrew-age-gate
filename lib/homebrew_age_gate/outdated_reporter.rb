# frozen_string_literal: true

require "json"

module HomebrewAgeGate
  class OutdatedReporter
    PASTEL_GREEN = "\e[38;2;119;221;119m"
    PASTEL_RED = "\e[38;2;255;154;162m"
    RESET = "\e[0m"

    IGNORE_PREFIXES = [
      "==>",
      "Warning:",
      "Error:",
      "No outdated",
      "`HOMEBREW_"
    ].freeze

    def initialize(config:, runner:, now: Time.now)
      @config = config
      @runner = runner
      @age_resolver = AgeResolver.new(runner: runner, now: now)
      @safe_version_resolver = SafeVersionResolver.new(
        runner: runner,
        now: now,
        min_age_days: config.min_age_days
      )
    end

    def annotate(output, color: false)
      names = package_names(output)
      return output if names.empty?

      packages = fetch_packages_from_names(names)
      packages_by_name = index_packages(packages)

      output.lines.map do |line|
        name = package_name_from_line(line)
        package = packages_by_name[name]
        package ? annotate_line(line, package, color: color) : line
      end.join
    end

    private

    attr_reader :config, :runner, :age_resolver, :safe_version_resolver

    def package_names(output)
      output.lines.map { |line| package_name_from_line(line) }.compact.uniq
    end

    def package_name_from_line(line)
      text = line.strip
      return nil if text.empty?
      return nil if IGNORE_PREFIXES.any? { |prefix| text.start_with?(prefix) }

      first = text.split(/\s+/, 2).first
      return nil unless first&.match?(/\A[A-Za-z0-9_.+@\/-]+\z/)
      return nil if first.match?(/\A\d/)

      first
    end

    def fetch_packages_from_names(names)
      output = runner.capture(["info", "--json=v2"] + names, env: frozen_env)
      payload = JSON.parse(output)
      formulae = payload.fetch("formulae", []).map { |info| Package.from_formula_info(info) }
      casks = payload.fetch("casks", []).map { |info| Package.from_cask_info(info) }
      formulae + casks
    rescue JSON::ParserError => e
      raise ConfigError, "Unable to parse brew info JSON: #{e.message}"
    end

    def index_packages(packages)
      packages.each_with_object({}) do |package, index|
        index[package.name] = package
        index[package.canonical_name] = package
      end
    end

    def annotate_line(line, package, color:)
      newline = line.end_with?("\n") ? "\n" : ""
      age_result = age_resolver.resolve(package)
      safe_version = safe_version_resolver.resolve(package, age_result)
      annotation = [
        format_annotation(package, age_result, color: color),
        format_safe_version(safe_version, color: color)
      ].compact.join(" -> ")
      "#{format_label(package.name, age_result, color: color)} #{annotation}#{newline}"
    end

    def format_annotation(package, age_result, color:)
      [
        "#{format_label("version:", age_result, color: color)} #{format_version(package)}",
        "#{format_label("age:", age_result, color: color)} #{format_age(age_result)}"
      ].join(" ")
    end

    def format_version(package)
      version = package.version.to_s
      return "unknown" if version.empty?

      version.split(",", 2).first
    end

    def format_safe_version(safe_version, color:)
      return nil unless safe_version

      [
        "#{format_label("version:", safe_version, color: color)} #{safe_version.version}",
        "#{format_label("age:", safe_version, color: color)} #{format_age(safe_version)}"
      ].join(" ")
    end

    def format_age(age_result)
      return "unknown" unless age_result.known?

      "#{age_result.age_seconds.floor / 86_400}d"
    end

    def format_label(text, age_result, color:)
      return text unless color

      color_code = if age_result.known? && age_result.age_seconds >= min_age_seconds
        PASTEL_GREEN
      else
        PASTEL_RED
      end
      "#{color_code}#{text}#{RESET}"
    end

    def min_age_seconds
      config.min_age_days * 86_400
    end

    def frozen_env
      { "HOMEBREW_NO_AUTO_UPDATE" => "1" }
    end
  end
end
