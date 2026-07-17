require "../spec_helper"

class CannedExecutor < Ssherlock::Executor
  def initialize(@out : String)
  end

  def exec(cmd : String) : String
    @out
  end
end

class CannedOpener < Ssherlock::Opener
  def initialize(@out : String)
  end

  def open(server : Ssherlock::Server, &block : Ssherlock::Executor -> Nil) : Nil
    block.call(CannedExecutor.new(@out))
  end
end

class RaisingOpener < Ssherlock::Opener
  def open(server : Ssherlock::Server, &_block : Ssherlock::Executor -> Nil) : Nil
    raise Ssherlock::Error.new("auth: nope")
  end
end

Spectator.describe Ssherlock::Collector do
  def logger
    Ssherlock::Logger.build(File.join(Dir.tempdir, "ae-c-#{Random.rand(100000)}"))
  end

  def server(checks)
    Ssherlock::Server.new(
      label: "l",
      target: Ssherlock::Endpoint.new("h", "h", 22, "root", "/k"),
      bastion: nil,
      timeout: 10, cmd_timeout: 20, sudo: false, wrap: false,
      verify_host_key: :never,
      checks: checks,
    )
  end

  it "collects each section and check into the envelope with metadata" do
    check = Ssherlock::Check.new(
      command: "grep x", description: "root login control",
      category: "security", severity: "high", expected: "no")
    checks = {"ssh" => {"root" => check}}
    env = Ssherlock::Collector.new(logger, false).collect(server(checks), CannedOpener.new("output"))
    expect(env.label).to eq("l")
    expect(env.error).to be_nil
    entry = env.data["ssh"]["root"]
    expect(entry.category).to eq("security")
    expect(entry.severity).to eq("high")
    expect(entry.expected).to eq("no")
    expect(entry.description).to eq("root login control")
    expect(entry.output).to eq("output")
  end

  it "emits fields in a fixed order and omits absent metadata" do
    all = Ssherlock::Check.new(
      command: "c", description: "d", category: "security", severity: "low", expected: "e")
    bare = Ssherlock::Check.new(command: "c")
    env = Ssherlock::Collector.new(logger, false).collect(
      server({"s" => {"full" => all, "min" => bare}}), CannedOpener.new("o"))
    expect(env.data["s"]["full"].to_json).to eq(
      %({"category":"security","severity":"low","expected":"e","description":"d","output":"o"}))
    expect(env.data["s"]["min"].to_json).to eq(%({"output":"o"}))
  end

  it "captures a connection error" do
    checks = {} of String => Hash(String, Ssherlock::Check)
    env = Ssherlock::Collector.new(logger, false).collect(server(checks), RaisingOpener.new)
    expect(env.error).to match(/auth: nope/)
    expect(env.data.empty?).to be_true
  end
end
