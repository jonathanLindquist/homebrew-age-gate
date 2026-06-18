# frozen_string_literal: true

require "rbconfig"

module HomebrewAgeGate
  class CLI
    def self.run(argv)
      command = argv.shift
      case command
      when "plan"
        upgrade_args = argv.dup
        upgrade_args.shift if upgrade_args.first == "upgrade"
        config = Config.load
        runner = BrewRunner.new(config.real_brew_path)
        planner = Planner.new(config: config, runner: runner)
        plan = planner.initial_plan(["upgrade"] + upgrade_args)
        Report.print_plan(plan)
        0
      when "doctor"
        run_doctor
      when "version", "--version", "-v"
        puts VERSION
        0
      else
        warn "Usage: homebrew-age-gate plan [upgrade args...] | doctor | version"
        2
      end
    rescue ConfigError, ArgParseError, CommandError => e
      warn "homebrew-age-gate: #{e.message}"
      1
    end

    def self.run_brew_wrapper(argv)
      config = Config.load
      runner = BrewRunner.new(config.real_brew_path)
      planner = Planner.new(config: config, runner: runner)
      plan = planner.initial_plan(argv)
      Report.print_plan(plan)

      if plan.allowed.empty?
        puts "homebrew-age-gate: no eligible packages to upgrade."
        return 0
      end

      allowed_names = plan.allowed_packages.map(&:canonical_name)
      parsed = plan.parsed_args
      preflight_args = ["upgrade"] + parsed.flags_without_dry_run + ["--dry-run"] + allowed_names
      stdout, stderr, status = runner.capture_with_status(preflight_args, env: planner.final_env)
      unless status.success?
        $stdout.write(stdout)
        $stderr.write(stderr)
        return status.exitstatus || 1
      end

      planned_names = DryRunParser.new.parse_package_names(stdout)
      if planned_names.empty?
        warn "homebrew-age-gate: could not parse any package names from brew upgrade --dry-run output; failing closed."
        return 1
      end

      preflight_plan = planner.validate_planned_names(parsed, planned_names)
      if preflight_plan.skipped.any?
        Report.print_blocked_preflight(preflight_plan)
        return 1
      end

      if parsed.dry_run?
        $stdout.write(stdout)
        return 0
      end

      final_args = ["upgrade"] + parsed.flags_without_dry_run + allowed_names
      runner.system(final_args, env: planner.final_env)
    rescue ConfigError, ArgParseError, CommandError => e
      warn "homebrew-age-gate: #{e.message}"
      1
    end

    def self.run_doctor
      config = Config.load
      problems = []

      problems << "real brew path is not executable: #{config.real_brew_path}" unless File.executable?(config.real_brew_path)
      problems << "git is not available on PATH" unless executable_on_path?("git")
      problems << "config path: #{config.path || "(none)"}"
      problems << "ruby: #{RbConfig.ruby}"

      if problems.any? { |problem| problem.start_with?("real brew", "git") }
        problems.each { |problem| warn problem }
        1
      else
        puts "homebrew-age-gate doctor ok"
        problems.each { |problem| puts "  #{problem}" }
        0
      end
    rescue ConfigError => e
      warn "homebrew-age-gate: #{e.message}"
      1
    end

    def self.executable_on_path?(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
        File.executable?(File.join(dir, name))
      end
    end
  end
end

