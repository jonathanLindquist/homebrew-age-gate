# frozen_string_literal: true

require "json"
require "digest"
require "net/http"
require "open3"
require "time"
require "uri"

module HomebrewAgeGate
  AgeResult = Struct.new(:known, :commit_time, :age_seconds, :reason, keyword_init: true) do
    def known?
      known
    end
  end

  class GitHubCommitHistory
    USER_AGENT = "homebrew-age-gate"

    def commit_time(tap:, repo:, revision:, path:)
      github_repo = github_repository(tap, repo)
      return nil unless github_repo

      uri = URI::HTTPS.build(
        host: "api.github.com",
        path: "/repos/#{github_repo}/commits",
        query: URI.encode_www_form(path: path, sha: revision, per_page: 1)
      )
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["User-Agent"] = USER_AGENT

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        http.request(request)
      end
      return nil unless response.is_a?(Net::HTTPSuccess)

      commits = JSON.parse(response.body)
      return nil unless commits.is_a?(Array) && commits.first.is_a?(Hash)

      date = commits.first.dig("commit", "committer", "date") || commits.first.dig("commit", "author", "date")
      date ? Time.iso8601(date) : nil
    rescue JSON::ParserError, ArgumentError, IOError, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError
      nil
    end

    private

    def github_repository(tap, repo)
      return "Homebrew/homebrew-#{tap.split("/", 2).fetch(1)}" if tap&.start_with?("homebrew/")

      remote = git_remote(repo)
      github_repository_from_remote(remote)
    end

    def git_remote(repo)
      stdout, _stderr, status = Open3.capture3("git", "-C", repo, "remote", "get-url", "origin")
      status.success? ? stdout.strip : nil
    rescue SystemCallError
      nil
    end

    def github_repository_from_remote(remote)
      return nil if remote.nil? || remote.empty?

      match = remote.match(%r{github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?\z})
      return nil unless match

      "#{match[:owner]}/#{match[:repo]}"
    end
  end

  class AgeResolver
    def initialize(runner:, now: Time.now, commit_history: GitHubCommitHistory.new)
      @runner = runner
      @now = now
      @commit_history = commit_history
      @tap_repo_cache = {}
      @age_cache = {}
    end

    def resolve(package)
      cache_key = [package.tap, package.tap_git_head, package.source_path, package.source_checksum]
      return @age_cache[cache_key] if @age_cache.key?(cache_key)

      result = resolve_uncached(package)
      @age_cache[cache_key] = result
      result
    end

    private

    attr_reader :runner, :now, :commit_history

    def resolve_uncached(package)
      return unknown("missing tap") if blank?(package.tap)
      return unknown("missing ruby_source_path") if blank?(package.source_path)

      repo = tap_repo(package.tap)
      return unknown("tap repository not found for #{package.tap}") if blank?(repo)

      unless blank?(package.tap_git_head)
        output = git_log(repo, package.tap_git_head, package.source_path)
        return known(Time.at(Integer(output.strip))) unless blank?(output)
      end

      if matching_local_source?(repo, package.source_path, package.source_checksum)
        output = git_log(repo, "HEAD", package.source_path)
        return known(Time.at(Integer(output.strip))) unless blank?(output)
      end

      unless blank?(package.tap_git_head)
        remote_commit_time = commit_history.commit_time(
          tap: package.tap,
          repo: repo,
          revision: package.tap_git_head,
          path: package.source_path
        )
        return known(remote_commit_time) if remote_commit_time

        return unknown("no git history for #{package.source_path}")
      end

      unknown("missing tap_git_head")
    rescue ArgumentError
      unknown("invalid git commit timestamp for #{package.source_path}")
    end

    def known(commit_time)
      AgeResult.new(
        known: true,
        commit_time: commit_time,
        age_seconds: now.to_i - commit_time.to_i,
        reason: nil
      )
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

    def matching_local_source?(repo, path, expected_checksum)
      return false if blank?(expected_checksum)

      local_path = File.join(repo, path)
      return false unless File.file?(local_path)

      Digest::SHA256.file(local_path).hexdigest == expected_checksum
    rescue SystemCallError
      false
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
