# frozen_string_literal: true

module HomebrewAgeGate
  class Report
    PASTEL_GREEN = "\e[38;2;119;221;119m"
    PASTEL_RED = "\e[38;2;255;154;162m"
    BOLD_WHITE = "\e[1;97m"
    RESET = "\e[0m"

    def self.print_plan(plan, io: $stdout, color: false)
      io.puts "homebrew-age-gate plan"
      io.puts

      if plan.allowed.empty?
        io.puts format_group_heading("Allowed: none", color: color)
      else
        io.puts format_group_heading("Allowed:", color: color)
        plan.allowed.each { |decision| io.puts "  #{format_decision(decision, color: color)}" }
      end

      io.puts

      if plan.skipped.empty?
        io.puts format_group_heading("Skipped: none", color: color)
      else
        io.puts format_group_heading("Skipped:", color: color)
        plan.skipped.each { |decision| io.puts "  #{format_decision(decision, color: color)}" }
      end
    end

    def self.print_blocked_preflight(plan, io: $stderr, color: false)
      io.puts "homebrew-age-gate: refusing to upgrade because the frozen dry-run plan includes blocked packages."
      plan.skipped.each { |decision| io.puts "  #{format_decision(decision, color: color)}" }
    end

    def self.print_deferred_preflight(deferred_roots, io: $stdout, color: false)
      return if deferred_roots.empty?

      io.puts "Deferred by dependency preflight:"
      deferred_roots.each do |deferred_root|
        package_name = format_package_name(deferred_root.package.canonical_name, allowed: true, color: color)
        io.puts "  #{package_name} blocked because dry-run includes blocked packages: #{blocked_summary(deferred_root.blocked_decisions, color: color)}"
        deferred_root.blocked_decisions.each { |decision| io.puts "    #{format_decision(decision, color: color)}" }
      end
    end

    def self.format_decision(decision, color: false)
      package = decision.package
      age_result = decision.age_result
      age = if age_result&.known?
        days = age_result.age_seconds / 86_400.0
        "#{days.round}d"
      elsif age_result
        "unknown"
      else
        "not checked"
      end
      package_name = format_package_name(package.canonical_name, allowed: decision.allowed?, color: color)
      [
        package_name,
        format_key_value("age", age, color: color),
        format_key_value("definition_commit_date", definition_commit_date_value(age_result), color: color),
        format_key_value("reason", decision.reason, color: color)
      ].join(" ")
    end

    def self.definition_commit_date(age_result)
      "definition_commit_date=#{definition_commit_date_value(age_result)}"
    end

    def self.definition_commit_date_value(age_result)
      return "not checked" unless age_result
      return "unknown" unless age_result.known?

      age_result.commit_time.utc.strftime("%Y-%m-%d")
    end

    def self.blocked_summary(decisions, color: false)
      decisions.map do |decision|
        package_name = format_package_name(decision.package.canonical_name, allowed: decision.allowed?, color: color)
        "#{package_name} (#{decision.reason})"
      end.join(", ")
    end

    def self.format_group_heading(text, color:)
      return text unless color

      "#{BOLD_WHITE}#{text}#{RESET}"
    end

    def self.format_key_value(field, value, color:)
      "#{format_field(field, color: color)}=#{value}"
    end

    def self.format_field(field, color:)
      return field unless color

      "#{BOLD_WHITE}#{field}#{RESET}"
    end

    def self.format_package_name(name, allowed:, color:)
      return name unless color

      color_code = allowed ? PASTEL_GREEN : PASTEL_RED
      "#{color_code}#{name}#{RESET}"
    end
  end
end
