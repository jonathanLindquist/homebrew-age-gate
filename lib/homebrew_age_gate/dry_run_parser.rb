# frozen_string_literal: true

module HomebrewAgeGate
  class DryRunParser
    IGNORE_PREFIXES = [
      "==>",
      "Warning:",
      "Error:",
      "Disable this behaviour",
      "`HOMEBREW_"
    ].freeze

    def parse_package_names(output)
      output.lines.map do |line|
        parse_line(line)
      end.compact.uniq
    end

    private

    def parse_line(line)
      text = line.strip
      return nil if text.empty?
      return nil if IGNORE_PREFIXES.any? { |prefix| text.start_with?(prefix) }

      text = text.sub(/\A[-*]\s+/, "")
      first = text.split(/\s+/, 2).first
      return nil unless first
      return nil unless first.match?(/\A[A-Za-z0-9_.+@\/-]+\z/)
      return nil if first =~ /\A\d/

      first
    end
  end
end
