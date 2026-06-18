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
  end
end
