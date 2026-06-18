# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "shellwords"
require "tmpdir"
require "time"

require "homebrew_age_gate"

module TestHelpers
  ROOT = File.expand_path("..", __dir__)

  def write_json(path, value)
    File.write(path, JSON.pretty_generate(value))
  end

  def make_fake_brew(dir)
    path = File.join(dir, "fake-brew")
    File.write(path, fake_brew_source)
    FileUtils.chmod("+x", path)
    path
  end

  def fake_env(dir, fake_brew, scenario_path, log_path, extra = {})
    {
      "HOME" => dir,
      "PATH" => ENV.fetch("PATH"),
      "FAKE_BREW_SCENARIO" => scenario_path,
      "FAKE_BREW_LOG" => log_path,
      "HOMEBREW_AGE_GATE_REAL_BREW" => fake_brew
    }.merge(extra)
  end

  def write_scenario(path, repos:, outdated:, formulae: [], casks: [], dry_run_output: "", dry_run_status: 0, upgrade_status: 0)
    write_json(path, {
      "repos" => repos,
      "outdated" => outdated,
      "formulae" => formulae,
      "casks" => casks,
      "dry_run_output" => dry_run_output,
      "dry_run_status" => dry_run_status,
      "upgrade_status" => upgrade_status
    })
  end

  def fake_brew_source
    <<~RUBY
      #!/usr/bin/env ruby
      # frozen_string_literal: true

      require "json"

      scenario = JSON.parse(File.read(ENV.fetch("FAKE_BREW_SCENARIO")))
      log_path = ENV.fetch("FAKE_BREW_LOG")
      entry = {
        "args" => ARGV,
        "env" => ENV.select { |key, _| key.start_with?("HOMEBREW_NO_") || key.start_with?("HOMEBREW_AGE_GATE_") }
      }
      File.open(log_path, "a") { |file| file.puts(JSON.generate(entry)) }

      def emit(value)
        puts JSON.generate(value)
      end

      def names_after_info_args(args)
        args[2..-1].reject { |arg| ["--formula", "--formulae", "--cask", "--casks"].include?(arg) }
      end

      case ARGV.first
      when "outdated"
        emit(scenario.fetch("outdated"))
      when "info"
        names = names_after_info_args(ARGV)
        formula_only = ARGV.include?("--formula") || ARGV.include?("--formulae")
        cask_only = ARGV.include?("--cask") || ARGV.include?("--casks")
        formulae = scenario.fetch("formulae", []).select do |item|
          names.empty? || names.include?(item["name"]) || names.include?("\#{item["tap"]}/\#{item["name"]}")
        end
        casks = scenario.fetch("casks", []).select do |item|
          token = item["token"] || item["full_token"]
          names.empty? || names.include?(token) || names.include?("\#{item["tap"]}/\#{token}")
        end
        emit({
          "formulae" => cask_only ? [] : formulae,
          "casks" => formula_only ? [] : casks
        })
      when "--repository"
        repo = scenario.fetch("repos").fetch(ARGV.fetch(1))
        puts repo
      when "upgrade"
        if ARGV.include?("--dry-run")
          print scenario.fetch("dry_run_output")
          exit scenario.fetch("dry_run_status", 0)
        end
        puts "fake upgrade \#{ARGV[1..-1].join(" ")}"
        exit scenario.fetch("upgrade_status", 0)
      else
        puts "fake pass-through \#{ARGV.join(" ")}"
      end
    RUBY
  end

  def read_log(path)
    return [] unless File.exist?(path)

    File.readlines(path).map { |line| JSON.parse(line) }
  end

  def run_bin(args, env:, chdir: ROOT)
    Open3.capture3(env, RbConfig.ruby, "-Ilib", *args, chdir: chdir)
  end

  def assert_no_real_brew_calls!(log_path)
    read_log(log_path).each do |entry|
      args = entry.fetch("args")
      refute_equal ["update"], args, "test attempted a brew update path"
      refute_equal ["upgrade"], args, "test attempted a bare brew upgrade path"
    end
  end

  def create_tap_repo(dir, files_with_age_days)
    repo = File.join(dir, "tap")
    FileUtils.mkdir_p(repo)
    system("git", "-C", repo, "init", out: File::NULL, err: File::NULL)
    system("git", "-C", repo, "config", "user.email", "test@example.com")
    system("git", "-C", repo, "config", "user.name", "Test User")

    files_with_age_days.each do |path, age_days|
      full_path = File.join(repo, path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, "# #{path}\\n")
      system("git", "-C", repo, "add", path)
      timestamp = Time.now - (age_days * 86_400)
      commit_env = {
        "GIT_AUTHOR_DATE" => timestamp.utc.iso8601,
        "GIT_COMMITTER_DATE" => timestamp.utc.iso8601
      }
      system(commit_env, "git", "-C", repo, "commit", "-m", "add #{path}", out: File::NULL, err: File::NULL)
    end

    head = `git -C #{repo.shellescape} rev-parse HEAD`.strip
    [repo, head]
  end

  def formula_info(name, tap:, path:, head:)
    {
      "name" => name,
      "tap" => tap,
      "versions" => { "stable" => "2.0.0" },
      "ruby_source_path" => path,
      "tap_git_head" => head
    }
  end

  def cask_info(token, tap:, path:, head:, version: "2.0.0", auto_updates: false)
    {
      "token" => token,
      "full_token" => token,
      "tap" => tap,
      "version" => version,
      "auto_updates" => auto_updates,
      "ruby_source_path" => path,
      "tap_git_head" => head
    }
  end
end

class Minitest::Test
  include TestHelpers
end
