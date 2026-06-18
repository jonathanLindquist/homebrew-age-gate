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

      parsed = plan.parsed_args
      batches = upgrade_batches(parsed, plan.allowed_packages)
      preflight_outputs = []

      batches.each do |batch|
        stdout, stderr, status = runner.capture_with_status(batch.preflight_args, env: planner.final_env)
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

        preflight_plan = planner.validate_planned_names(parsed, planned_names, type: batch.type)
        if preflight_plan.skipped.any?
          Report.print_blocked_preflight(preflight_plan)
          return 1
        end

        preflight_outputs << stdout
      end

      if parsed.dry_run?
        preflight_outputs.each { |output| $stdout.write(output) }
        return 0
      end

      batches.each do |batch|
        status = runner.system(batch.final_args, env: planner.final_env)
        return status unless status.zero?
      end

      0
    rescue ConfigError, ArgParseError, CommandError => e
      warn "homebrew-age-gate: #{e.message}"
      1
    end

    def self.run_brew_outdated(argv)
      config = Config.load
      runner = BrewRunner.new(config.real_brew_path)
      stdout, stderr, status = runner.capture_with_status(argv)
      $stderr.write(stderr)

      if json_output?(argv)
        $stdout.write(stdout)
      else
        reporter = OutdatedReporter.new(config: config, runner: runner)
        $stdout.write(reporter.annotate(stdout, color: color_enabled?))
      end
      status.success? ? 0 : (status.exitstatus || 1)
    rescue ConfigError, CommandError => e
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

    def self.json_output?(argv)
      argv.any? { |arg| arg == "--json" || arg.start_with?("--json=") }
    end

    def self.color_enabled?(env = ENV, io = $stdout)
      case env["HOMEBREW_AGE_GATE_COLOR"]
      when "always"
        true
      when "never"
        false
      else
        !env.key?("NO_COLOR") && io.tty?
      end
    end

    def self.executable_on_path?(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
        File.executable?(File.join(dir, name))
      end
    end

    UpgradeBatch = Struct.new(:type, :packages, :flags, keyword_init: true) do
      def names
        packages.map(&:canonical_name)
      end

      def preflight_args
        ["upgrade"] + flags + ["--dry-run"] + names
      end

      def final_args
        ["upgrade"] + flags + names
      end
    end

    def self.upgrade_batches(parsed, packages)
      [
        typed_upgrade_batch(parsed, packages, :formula),
        typed_upgrade_batch(parsed, packages, :cask)
      ].compact
    end

    def self.typed_upgrade_batch(parsed, packages, type)
      typed_packages = packages.select { |package| package.type == type }
      return nil if typed_packages.empty?

      UpgradeBatch.new(type: type, packages: typed_packages, flags: typed_upgrade_flags(parsed, type))
    end

    def self.typed_upgrade_flags(parsed, type)
      flags = parsed.flags_without_dry_run
      return flags if flags.any? { |flag| %w[--formula --formulae --cask --casks].include?(flag) }

      flags + [type == :formula ? "--formula" : "--cask"]
    end
  end
end
