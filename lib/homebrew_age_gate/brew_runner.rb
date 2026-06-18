# frozen_string_literal: true

require "open3"

module HomebrewAgeGate
  class CommandError < StandardError
    attr_reader :args, :stdout, :stderr, :status

    def initialize(args, stdout, stderr, status)
      @args = args
      @stdout = stdout
      @stderr = stderr
      @status = status
      super("Command failed: brew #{args.join(" ")}")
    end
  end

  class BrewRunner
    attr_reader :real_brew_path

    def initialize(real_brew_path)
      @real_brew_path = real_brew_path
    end

    def capture(args, env: {})
      stdout, stderr, status = Open3.capture3(env, real_brew_path, *args)
      raise CommandError.new(args, stdout, stderr, status) unless status.success?

      stdout
    end

    def capture_with_status(args, env: {})
      stdout, stderr, status = Open3.capture3(env, real_brew_path, *args)
      [stdout, stderr, status]
    end

    def system(args, env: {})
      Kernel.system(env, real_brew_path, *args)
      $?.exitstatus || 1
    end
  end
end
