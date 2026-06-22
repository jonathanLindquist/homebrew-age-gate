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
        color = color_enabled?
        Report.print_plan(plan, color: color)
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
      color = color_enabled?
      Report.print_plan(plan, color: color)

      if plan.allowed.empty?
        puts "homebrew-age-gate: no eligible packages to upgrade."
        return 0
      end

      parsed = plan.parsed_args
      batches = upgrade_batches(parsed, plan.allowed_packages)
      preflight = UpgradePreflight.new(planner: planner, runner: runner, parsed_args: parsed, color: color).filter(batches)
      if preflight.failure
        return handle_preflight_failure(preflight.failure)
      end

      Report.print_deferred_preflight(preflight.deferred_roots, color: color)

      if preflight.approved_batches.empty?
        puts "homebrew-age-gate: no safely upgradeable packages after dependency preflight."
        return 0
      end

      if parsed.dry_run?
        preflight.dry_run_outputs.each { |output| $stdout.write(output) }
        return 0
      end

      preflight.approved_batches.each do |batch|
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
        $stdout.write(annotate_outdated_output(reporter, stdout))
      end
      status.success? ? 0 : (status.exitstatus || 1)
    rescue ConfigError, CommandError => e
      warn "homebrew-age-gate: #{e.message}"
      1
    end

    def self.run_doctor
      config = Config.load
      problems = []

      unless File.executable?(config.real_brew_path)
        problems << "real brew path is not executable: #{display_path(config.real_brew_path)}"
      end
      problems << "git is not available on PATH" unless executable_on_path?("git")
      problems << "config path: #{display_path(config.path)}"
      problems << "homebrew config path: #{homebrew_trust_path}"
      problems << "ruby: #{display_path(RbConfig.ruby)}"

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

    def self.annotate_outdated_output(reporter, stdout)
      reporter.annotate(stdout, color: color_enabled?)
    rescue ConfigError, CommandError => e
      warn "homebrew-age-gate: unable to annotate brew outdated output: #{e.message}"
      warn e.stderr.to_s.strip if e.respond_to?(:stderr) && !e.stderr.to_s.strip.empty?
      stdout
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

    def self.display_path(path)
      HomebrewEnv.display_path(path)
    end

    def self.homebrew_trust_path
      config_home = HomebrewEnv.user_config_home
      return "(none)" unless config_home

      "#{display_path(config_home)}/trust.json"
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

      def with_packages(new_packages)
        self.class.new(type: type, packages: new_packages, flags: flags)
      end
    end

    def self.handle_preflight_failure(failure)
      if failure.write_command_output
        $stdout.write(failure.stdout)
        $stderr.write(failure.stderr)
      end
      warn failure.message if failure.message
      failure.exitstatus
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
