# frozen_string_literal: true

require "json"

module HomebrewAgeGate
  Decision = Struct.new(:package, :allowed, :reason, :age_result, keyword_init: true) do
    def allowed?
      allowed
    end
  end

  Plan = Struct.new(:parsed_args, :decisions, keyword_init: true) do
    def allowed
      decisions.select(&:allowed?)
    end

    def skipped
      decisions.reject(&:allowed?)
    end

    def allowed_packages
      allowed.map(&:package)
    end
  end

  class Planner
    def initialize(config:, runner:, now: Time.now)
      @config = config
      @runner = runner
      @arg_parser = ArgParser.new
      @age_resolver = AgeResolver.new(runner: runner, now: now)
    end

    def initial_plan(argv)
      parsed = @arg_parser.parse(argv)
      candidates = outdated_candidates(parsed)
      packages = fetch_packages(candidates)
      decisions = packages.map { |package| decide(package) }
      Plan.new(parsed_args: parsed, decisions: decisions)
    end

    def validate_planned_names(parsed_args, names, type: nil)
      packages = fetch_packages_from_names(names, type: type)
      missing = names.reject do |name|
        packages.any? { |package| package.name == name || package.canonical_name == name }
      end

      decisions = packages.map { |package| decide(package) }
      missing.each do |name|
        package = Package.new(
          type: :formula,
          name: name,
          tap: nil,
          source_path: nil,
          tap_git_head: nil,
          version: nil,
          auto_updates: false
        )
        decisions << Decision.new(
          package: package,
          allowed: false,
          reason: "unparseable planned package",
          age_result: AgeResult.new(known: false, reason: "not found in brew info")
        )
      end

      Plan.new(parsed_args: parsed_args, decisions: decisions)
    end

    def final_env
      env = {
        "HOMEBREW_NO_AUTO_UPDATE" => "1",
        "HOMEBREW_NO_INSTALL_CLEANUP" => "1"
      }
      unless config.unsafe_preserve_installed_dependents_check?
        env["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] = "1"
      end
      env
    end

    private

    attr_reader :config, :runner, :arg_parser, :age_resolver

    def outdated_candidates(parsed)
      args = ["outdated", "--json=v2"] + outdated_discovery_flags(parsed) + parsed.names
      payload = JSON.parse(runner.capture(args))
      formulae = payload.fetch("formulae", []).map { |item| [:formula, item.fetch("name")] }
      casks = payload.fetch("casks", []).map { |item| [:cask, item.fetch("name")] }
      formulae + casks
    rescue JSON::ParserError => e
      raise ConfigError, "Unable to parse brew outdated JSON: #{e.message}"
    end

    def outdated_discovery_flags(parsed)
      return parsed.outdated_flags unless parsed.names.empty?
      return parsed.outdated_flags if parsed.outdated_flags.any? { |flag| %w[--formula --formulae --cask --casks].include?(flag) }

      parsed.outdated_flags + ["--formula"]
    end

    def fetch_packages(candidates)
      formula_names = candidates.select { |type,| type == :formula }.map { |_, name| name }
      cask_names = candidates.select { |type,| type == :cask }.map { |_, name| name }

      packages = []
      packages.concat(fetch_info(formula_names, :formula)) unless formula_names.empty?
      packages.concat(fetch_info(cask_names, :cask)) unless cask_names.empty?
      packages
    end

    def fetch_packages_from_names(names, type: nil)
      return [] if names.empty?

      return fetch_info(names, type) if type

      output = runner.capture(["info", "--json=v2"] + names, env: final_env)
      payload = JSON.parse(output)
      packages_from_payload(payload)
    rescue JSON::ParserError => e
      raise ConfigError, "Unable to parse brew info JSON: #{e.message}"
    end

    def fetch_info(names, type)
      flag = type == :formula ? "--formula" : "--cask"
      output = runner.capture(["info", "--json=v2", flag] + names, env: final_env)
      payload = JSON.parse(output)
      packages_from_payload(payload)
    rescue JSON::ParserError => e
      raise ConfigError, "Unable to parse brew info JSON: #{e.message}"
    end

    def packages_from_payload(payload)
      formulae = payload.fetch("formulae", []).map { |info| Package.from_formula_info(info) }
      casks = payload.fetch("casks", []).map { |info| Package.from_cask_info(info) }
      formulae + casks
    end

    def decide(package)
      if package.auto_updates_cask? && !config.allow_auto_updates_cask?(package)
        return Decision.new(package: package, allowed: false, reason: "cask auto_updates true", age_result: nil)
      end

      age = age_resolver.resolve(package)
      unless age.known?
        allowed = config.unsafe_allow_unknown_age?(package)
        return Decision.new(
          package: package,
          allowed: allowed,
          reason: allowed ? "unknown age allowed by unsafe config" : "unknown age: #{age.reason}",
          age_result: age
        )
      end

      min_age_seconds = config.min_age_days * 86_400
      if age.age_seconds >= min_age_seconds
        Decision.new(package: package, allowed: true, reason: "old enough", age_result: age)
      else
        Decision.new(package: package, allowed: false, reason: "too new", age_result: age)
      end
    end
  end
end
