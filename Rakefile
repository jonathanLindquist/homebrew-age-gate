# frozen_string_literal: true

task default: :test

task :test do
  Dir["test/*_test.rb"].sort.each do |path|
    ruby "-Ilib:test", path
  end
end
