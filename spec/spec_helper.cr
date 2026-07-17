require "spectator"
require "crystal-env/spec"

Spectator.configure do |config|
  config.randomize
end

require "../src/ssherlock"

def fixture_path(name : String) : String
  File.expand_path("fixtures/#{name}", __DIR__)
end
