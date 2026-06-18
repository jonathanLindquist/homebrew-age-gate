# frozen_string_literal: true

module HomebrewAgeGate
  class ArgParseError < StandardError; end

  class ParsedUpgradeArgs
    attr_reader :flags, :names, :outdated_flags, :dry_run

    def initialize(flags:, names:, outdated_flags:, dry_run:)
      @flags = flags
      @names = names
      @outdated_flags = outdated_flags
      @dry_run = dry_run
    end

    def dry_run?
      @dry_run
    end

    def flags_without_dry_run
      flags.reject { |arg| ["-n", "--dry-run"].include?(arg) }
    end
  end

  class ArgParser
    SWITCHES = %w[
      -d --debug --display-times -f --force -v --verbose -n --dry-run
      -y --no-ask --yes --formula --formulae -s --build-from-source
      -i --interactive --force-bottle --fetch-HEAD --keep-tmp --debug-symbols
      --overwrite --cask --casks --skip-cask-deps --no-quit -g --greedy
      --greedy-latest --greedy-auto-updates --binaries --no-binaries
      --require-sha -q --quiet
    ].freeze

    VALUE_FLAGS = %w[
      --minimum-version --min-version --appdir --appimagedir --keyboard-layoutdir
      --colorpickerdir --prefpanedir --qlplugindir --mdimporterdir --dictionarydir
      --fontdir --servicedir --input-methoddir --internet-plugindir
      --audio-unit-plugindir --vst-plugindir --vst3-plugindir
      --screen-saverdir --language
    ].freeze

    OUTDATED_SWITCHES = %w[
      --formula --formulae --cask --casks --fetch-HEAD -g --greedy
      --greedy-latest --greedy-auto-updates
    ].freeze

    OUTDATED_VALUE_FLAGS = %w[--minimum-version --min-version].freeze

    def parse(argv)
      args = argv.dup
      args.shift if args.first == "upgrade"

      flags = []
      outdated_flags = []
      names = []
      dry_run = false
      index = 0

      while index < args.length
        arg = args.fetch(index)

        if arg == "--"
          raise ArgParseError, "`--` is ambiguous for homebrew-age-gate upgrade parsing"
        elsif SWITCHES.include?(arg)
          flags << arg
          outdated_flags << arg if OUTDATED_SWITCHES.include?(arg)
          dry_run = true if ["-n", "--dry-run"].include?(arg)
          index += 1
        elsif value_flag_token?(arg)
          flag, value, consumed = parse_value_flag(args, index)
          original = consumed == 1 ? "#{flag}=#{value}" : [flag, value]
          flags.concat(Array(original))

          if OUTDATED_VALUE_FLAGS.include?(flag)
            outdated_flags.concat(Array(original))
          end
          index += consumed
        elsif arg.start_with?("-")
          raise ArgParseError, "Unsupported or unsafe brew upgrade flag: #{arg}"
        else
          names << arg
          index += 1
        end
      end

      ParsedUpgradeArgs.new(flags: flags, names: names, outdated_flags: outdated_flags, dry_run: dry_run)
    end

    private

    def value_flag_token?(arg)
      VALUE_FLAGS.include?(arg) || VALUE_FLAGS.any? { |flag| arg.start_with?("#{flag}=") }
    end

    def parse_value_flag(args, index)
      arg = args.fetch(index)
      if arg.include?("=")
        flag, value = arg.split("=", 2)
        raise ArgParseError, "#{flag} requires a value" if value.empty?

        return [flag, value, 1]
      end

      value = args[index + 1]
      raise ArgParseError, "#{arg} requires a value" if value.nil? || value.start_with?("-")

      [arg, value, 2]
    end
  end
end

