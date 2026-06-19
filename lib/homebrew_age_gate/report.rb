# frozen_string_literal: true

module HomebrewAgeGate
  class Report
    def self.print_plan(plan, io: $stdout)
      io.puts "homebrew-age-gate plan"

      if plan.allowed.empty?
        io.puts "Allowed: none"
      else
        io.puts "Allowed:"
        plan.allowed.each { |decision| io.puts "  #{format_decision(decision)}" }
      end

      if plan.skipped.empty?
        io.puts "Skipped: none"
      else
        io.puts "Skipped:"
        plan.skipped.each { |decision| io.puts "  #{format_decision(decision)}" }
      end
    end

    def self.print_blocked_preflight(plan, io: $stderr)
      io.puts "homebrew-age-gate: refusing to upgrade because the frozen dry-run plan includes blocked packages."
      plan.skipped.each { |decision| io.puts "  #{format_decision(decision)}" }
    end

    def self.print_deferred_preflight(deferred_roots, io: $stdout)
      return if deferred_roots.empty?

      io.puts "Deferred by dependency preflight:"
      deferred_roots.each do |deferred_root|
        io.puts "  #{deferred_root.package.canonical_name} blocked because dry-run includes blocked packages: #{blocked_summary(deferred_root.blocked_decisions)}"
        deferred_root.blocked_decisions.each { |decision| io.puts "    #{format_decision(decision)}" }
      end
    end

    def self.format_decision(decision)
      package = decision.package
      age_result = decision.age_result
      age = if age_result&.known?
        days = age_result.age_seconds / 86_400.0
        "age=#{format("%.2f", days)}d"
      elsif age_result
        "age=unknown"
      else
        "age=not checked"
      end
      "#{package.canonical_name} #{age} #{definition_commit_date(age_result)} reason=#{decision.reason}"
    end

    def self.definition_commit_date(age_result)
      return "definition_commit_date=not checked" unless age_result
      return "definition_commit_date=unknown" unless age_result.known?

      "definition_commit_date=#{age_result.commit_time.utc.strftime("%Y-%m-%d")}"
    end

    def self.blocked_summary(decisions)
      decisions.map { |decision| "#{decision.package.canonical_name} (#{decision.reason})" }.join(", ")
    end
  end
end
