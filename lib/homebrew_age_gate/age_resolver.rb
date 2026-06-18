# frozen_string_literal: true

require "time"
require "open3"

module HomebrewAgeGate
  AgeResult = Struct.new(:known, :commit_time, :age_seconds, :reason, keyword_init: true) do
    def known?
      known
    end
  end

  class AgeResolver
    def initialize(runner:, now: Time.now)
      @runner = runner
      @now = now
      @tap_repo_cache = {}
      @age_cache = {}
    end

    def resolve(package)
      cache_key = [package.tap, package.tap_git_head, package.source_path]
      return @age_cache[cache_key] if @age_cache.key?(cache_key)

      result = resolve_uncached(package)
      @age_cache[cache_key] = result
      result
    end

    private

    attr_reader :runner, :now

    def resolve_uncached(package)
      return unknown("missing tap") if blank?(package.tap)
      return unknown("missing ruby_source_path") if blank?(package.source_path)
      return unknown("missing tap_git_head") if blank?(package.tap_git_head)

      repo = tap_repo(package.tap)
      return unknown("tap repository not found for #{package.tap}") if blank?(repo)

      output = git_log(repo, package.tap_git_head, package.source_path)
      return unknown("no git history for #{package.source_path}") if blank?(output)

      commit_epoch = Integer(output.strip)
      commit_time = Time.at(commit_epoch)
      AgeResult.new(
        known: true,
        commit_time: commit_time,
        age_seconds: now.to_i - commit_time.to_i,
        reason: nil
      )
    rescue ArgumentError
      unknown("invalid git commit timestamp for #{package.source_path}")
    end

    def tap_repo(tap)
      @tap_repo_cache[tap] ||= runner.capture(["--repository", tap], env: frozen_env).strip
    rescue CommandError
      nil
    end

    def git_log(repo, revision, path)
      stdout, = Open3.capture3("git", "-C", repo, "log", "-1", "--format=%ct", revision, "--", path)
      stdout
    rescue SystemCallError
      ""
    end

    def unknown(reason)
      AgeResult.new(known: false, commit_time: nil, age_seconds: nil, reason: reason)
    end

    def blank?(value)
      value.nil? || value.to_s.empty?
    end

    def frozen_env
      { "HOMEBREW_NO_AUTO_UPDATE" => "1" }
    end
  end
end
