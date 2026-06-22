# frozen_string_literal: true

require "json"

module HomebrewAgeGate
  OutdatedTableRow = Struct.new(
    :type,
    :name,
    :current_version,
    :latest_version,
    :age,
    :age_result,
    :safe_version,
    :safe_age,
    keyword_init: true
  )

  class OutdatedReporter
    PASTEL_GREEN = "\e[38;2;119;221;119m"
    PASTEL_RED = "\e[38;2;255;154;162m"
    PASTEL_ORANGE = "\e[38;2;255;190;120m"
    UNDERLINE = "\e[4m"
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
      current_versions_by_name = extract_current_versions_by_name(output)
      rows_by_name = build_rows_by_name(names, packages_by_name, current_versions_by_name)
      return output if rows_by_name.empty?

      passthrough = output.lines.reject do |line|
        rows_by_name.key?(package_name_from_line(line))
      end.join
      passthrough << "\n" unless passthrough.empty? || passthrough.end_with?("\n")

      passthrough + format_grouped_tables(rows_by_name.values, color: color)
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

    def extract_current_versions_by_name(output)
      output.lines.each_with_object({}) do |line, versions|
        name = package_name_from_line(line)
        next unless name

        versions[name] = current_version_from_line(line, name)
      end
    end

    def current_version_from_line(line, name)
      remainder = line.strip.sub(/\A#{Regexp.escape(name)}\b\s*/, "")
      token = remainder.split(/\s+/, 2).first
      return "unknown" if token.nil? || token.empty? || token.start_with?("<", ">", "=", "!")

      format_version_value(token.delete_prefix("(").delete_suffix(")"))
    end

    def fetch_packages_from_names(names)
      fetch_packages(["info", "--json=v2"] + names)
    rescue CommandError
      fetch_packages_individually(names)
    end

    def fetch_packages(args)
      output = runner.capture(args, env: frozen_env)
      payload = JSON.parse(output)
      formulae = payload.fetch("formulae", []).map { |info| Package.from_formula_info(info) }
      casks = payload.fetch("casks", []).map { |info| Package.from_cask_info(info) }
      formulae + casks
    rescue JSON::ParserError => e
      raise ConfigError, "Unable to parse brew info JSON: #{e.message}"
    end

    def fetch_packages_individually(names)
      names.flat_map do |name|
        fetch_packages(["info", "--json=v2", name])
      rescue ConfigError, CommandError => e
        warn_annotation_failure(name, e)
        []
      end
    end

    def warn_annotation_failure(name, error)
      warn "homebrew-age-gate: unable to annotate #{name}: #{error.message}"
      stderr = error.stderr.to_s.strip if error.respond_to?(:stderr)
      warn stderr unless stderr.to_s.empty?
    end

    def index_packages(packages)
      packages.each_with_object({}) do |package, index|
        index[package.name] = package
        index[package.canonical_name] = package
      end
    end

    def build_rows_by_name(names, packages_by_name, current_versions_by_name)
      names.each_with_object({}) do |name, rows|
        package = packages_by_name[name]
        next unless package

        age_result = age_resolver.resolve(package)
        safe_version = safe_version_resolver.resolve(package, age_result)
        rows[name] = OutdatedTableRow.new(
          type: package.type,
          name: package.name,
          current_version: current_version(name, package, current_versions_by_name),
          latest_version: format_version(package),
          age: format_age(age_result),
          age_result: age_result,
          safe_version: safe_version&.version,
          safe_age: safe_version ? format_age(safe_version) : nil
        )
      end
    end

    def format_grouped_tables(rows, color:)
      [
        [:formula, "Formulae"],
        [:cask, "Casks"]
      ].filter_map do |type, title|
        group_rows = rows.select { |row| row.type == type }.sort_by { |row| row.name.downcase }
        next if group_rows.empty?

        widths = table_widths(group_rows)
        [
          "#{title}\n",
          format_table_header(widths, color: color),
          group_rows.map { |row| format_table_row(row, widths, color: color) }.join
        ].join
      end.join("\n")
    end

    def table_widths(rows)
      include_safe = rows.any?(&:safe_version)
      widths = {
        name: "name".length,
        current_version: "current version".length,
        latest_version: "latest version".length,
        age: "age".length
      }

      if include_safe
        widths[:safe_version] = "safe version".length
        widths[:safe_age] = "safe age".length
      end

      rows.each do |row|
        widths[:name] = [widths.fetch(:name), row.name.length].max
        widths[:current_version] = [widths.fetch(:current_version), row.current_version.length].max
        widths[:latest_version] = [widths.fetch(:latest_version), row.latest_version.length].max
        widths[:age] = [widths.fetch(:age), row.age.length].max
        next unless include_safe

        widths[:safe_version] = [widths.fetch(:safe_version), row.safe_version.to_s.length].max
        widths[:safe_age] = [widths.fetch(:safe_age), row.safe_age.to_s.length].max
      end

      widths
    end

    def format_table_header(widths, color:)
      cells = [
        [format_header_label("name", color: color), "name", widths.fetch(:name)],
        [format_header_label("current version", color: color), "current version", widths.fetch(:current_version)],
        [format_header_label("latest version", color: color), "latest version", widths.fetch(:latest_version)],
        [format_header_label("age", color: color), "age", widths.fetch(:age)]
      ]
      if widths.key?(:safe_version)
        cells << [format_header_label("safe version", color: color), "safe version", widths.fetch(:safe_version)]
        cells << [format_header_label("safe age", color: color), "safe age", widths.fetch(:safe_age)]
      end

      format_table_cells(cells)
    end

    def format_table_row(row, widths, color:)
      cells = [
        [format_label(row.name, row.age_result, color: color), row.name, widths.fetch(:name)],
        [row.current_version, row.current_version, widths.fetch(:current_version)],
        [row.latest_version, row.latest_version, widths.fetch(:latest_version)],
        [row.age, row.age, widths.fetch(:age)]
      ]

      if widths.key?(:safe_version)
        cells << [row.safe_version.to_s, row.safe_version.to_s, widths.fetch(:safe_version)]
        cells << [row.safe_age.to_s, row.safe_age.to_s, widths.fetch(:safe_age)]
      end

      format_table_cells(cells)
    end

    def format_table_cells(cells)
      cells.map do |display, value, width|
        pad_cell(display, value, width)
      end.join("  ").rstrip + "\n"
    end

    def pad_cell(display, value, width)
      display + (" " * [width - value.length, 0].max)
    end

    def format_version(package)
      format_version_value(package.version)
    end

    def current_version(name, package, current_versions_by_name)
      output_version = current_versions_by_name[name]
      return output_version unless unknown_version?(output_version)

      format_version_values(package.installed_versions)
    end

    def format_version_values(values)
      versions = values.map { |value| format_version_value(value) }.reject { |value| unknown_version?(value) }.uniq
      return "unknown" if versions.empty?

      versions.join(", ")
    end

    def format_version_value(value)
      version = value.to_s
      return "unknown" if version.empty?

      version.split(",", 2).first
    end

    def unknown_version?(value)
      value.nil? || value.empty? || value == "unknown"
    end

    def format_age(age_result)
      return "unknown" unless age_result.known?

      "#{age_result.age_seconds.floor / 86_400}d"
    end

    def format_label(text, age_result, color:)
      return text unless color

      color_code = if age_result.known? && age_result.age_seconds > min_age_seconds
        PASTEL_GREEN
      else
        PASTEL_RED
      end
      "#{color_code}#{text}#{RESET}"
    end

    def format_header_label(text, color:)
      return text unless color

      "#{PASTEL_ORANGE}#{UNDERLINE}#{text}#{RESET}"
    end

    def min_age_seconds
      config.min_age_days * 86_400
    end

    def frozen_env
      { "HOMEBREW_NO_AUTO_UPDATE" => "1" }
    end
  end
end
