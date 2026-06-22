# frozen_string_literal: true

require "digest"
require "open3"
require "time"

module HomebrewAgeGate
  SafeVersion = Struct.new(:version, :commit_time, :age_seconds, keyword_init: true) do
    def known?
      true
    end
  end

  class SafeVersionResolver
    SEMANTIC_VERSION = /(?<!\d)(\d+(?:\.\d+)+(?:[-_][A-Za-z0-9][A-Za-z0-9._-]*)?)(?!\d)/

    def initialize(runner:, now: Time.now, min_age_days:)
      @runner = runner
      @now = now
      @min_age_seconds = min_age_days * 86_400
      @tap_repo_cache = {}
      @safe_version_cache = {}
    end

    def resolve(package, current_age_result)
      return nil unless current_age_result&.known?
      return nil if current_age_result.age_seconds > min_age_seconds

      cache_key = [package.tap, package.tap_git_head, package.source_path, package.source_checksum]
      return @safe_version_cache[cache_key] if @safe_version_cache.key?(cache_key)

      @safe_version_cache[cache_key] = resolve_uncached(package)
    end

    private

    attr_reader :runner, :now, :min_age_seconds

    def resolve_uncached(package)
      return nil if blank?(package.tap) || blank?(package.source_path)

      repo = tap_repo(package.tap)
      return nil if blank?(repo)

      revision = local_revision_for(package, repo)
      return nil if blank?(revision)

      safe_commit = latest_safe_commit(repo, revision, package.source_path)
      return nil unless safe_commit

      sha, commit_epoch = safe_commit
      content = git_show(repo, sha, package.source_path)
      version = extract_version(content)
      return nil if blank?(version)

      commit_time = Time.at(commit_epoch)
      SafeVersion.new(
        version: version,
        commit_time: commit_time,
        age_seconds: now.to_i - commit_time.to_i
      )
    end

    def local_revision_for(package, repo)
      if !blank?(package.tap_git_head) && git_revision?(repo, package.tap_git_head)
        return package.tap_git_head
      end

      return "HEAD" if matching_local_source?(repo, package.source_path, package.source_checksum)

      nil
    end

    def latest_safe_commit(repo, revision, path)
      cutoff_time = Time.at(now.to_i - min_age_seconds - 1).utc.iso8601
      sha = git_rev_list_before(repo, revision, path, cutoff_time)
      return nil if blank?(sha)

      epoch = git_commit_epoch(repo, sha)
      return nil if blank?(epoch)

      [sha, Integer(epoch)]
    rescue ArgumentError
      nil
    end

    def extract_version(content)
      explicit_version = content[/^\s*version\s+["']([^"']+)["']/, 1]
      return normalize_version(explicit_version) if explicit_version

      url = content[/^\s*url\s+["']([^"']+)["']/, 1]
      url_version = infer_version_from_url(url)
      return url_version if url_version

      tag_version = infer_version_from_option(content, "tag")
      return tag_version if tag_version

      revision_version = infer_version_from_option(content, "revision")
      return revision_version if revision_version

      nil
    end

    def normalize_version(version)
      semantic_version = version.to_s.split(",", 2).first&.match(SEMANTIC_VERSION)
      semantic_version && semantic_version[1]
    end

    def infer_version_from_url(url)
      return nil if blank?(url)
      return nil if url.include?('#{')

      candidates = url.scan(SEMANTIC_VERSION).flatten
      normalize_version(candidates.last)
    end

    def infer_version_from_option(content, option)
      value = content[/\b#{Regexp.escape(option)}:\s*["']([^"']+)["']/, 1]
      normalize_version(value)
    end

    def tap_repo(tap)
      @tap_repo_cache[tap] ||= runner.capture(["--repository", tap], env: frozen_env).strip
    rescue CommandError
      nil
    end

    def git_revision?(repo, revision)
      _stdout, _stderr, status = Open3.capture3("git", "-C", repo, "cat-file", "-e", "#{revision}^{commit}")
      status.success?
    rescue SystemCallError
      false
    end

    def git_rev_list_before(repo, revision, path, cutoff_time)
      stdout, _stderr, status = Open3.capture3(
        "git",
        "-C",
        repo,
        "rev-list",
        "-1",
        "--before=#{cutoff_time}",
        revision,
        "--",
        path
      )
      status.success? ? stdout.strip : ""
    rescue SystemCallError
      ""
    end

    def git_commit_epoch(repo, revision)
      stdout, _stderr, status = Open3.capture3("git", "-C", repo, "show", "-s", "--format=%ct", revision)
      status.success? ? stdout.strip : nil
    rescue SystemCallError
      nil
    end

    def git_show(repo, revision, path)
      stdout, _stderr, status = Open3.capture3("git", "-C", repo, "show", "#{revision}:#{path}")
      status.success? ? stdout : ""
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

    def blank?(value)
      value.nil? || value.to_s.empty?
    end

    def frozen_env
      { "HOMEBREW_NO_AUTO_UPDATE" => "1" }
    end
  end
end
