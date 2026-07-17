require "../spec_helper"

class FakeExecutor < Ssherlock::Executor
  def initialize(@out : String? = nil, @raise : Exception? = nil)
    @seen = [] of String
  end

  getter seen : Array(String)

  def exec(cmd : String) : String
    @seen << cmd
    if ex = @raise
      raise ex
    end
    @out || ""
  end
end

Spectator.describe Ssherlock::CheckRunner do
  def server(wrap : Bool, sudo : Bool = false)
    Ssherlock::Server.new(
      label: "l",
      target: Ssherlock::Endpoint.new("h", "h", 22, "root", "/k"),
      bastion: nil,
      timeout: 10, cmd_timeout: 20, sudo: sudo, wrap: wrap,
      verify_host_key: :never,
      checks: {} of String => Hash(String, Ssherlock::Check),
    )
  end

  it "wraps the command with timeout when wrap is true" do
    fake = FakeExecutor.new("ok")
    result = Ssherlock::CheckRunner.run(fake, "lscpu", server(true), false)
    expect(result).to eq("ok")
    expect(fake.seen.first).to eq("timeout 20 sh -c lscpu")
  end

  it "prefixes sudo when enabled" do
    fake = FakeExecutor.new("ok")
    Ssherlock::CheckRunner.run(fake, "lscpu", server(true, true), false)
    expect(fake.seen.first).to eq("sudo timeout 20 sh -c lscpu")
  end

  it "runs raw when wrap is false" do
    fake = FakeExecutor.new("ok")
    Ssherlock::CheckRunner.run(fake, "esxcli x", server(false), false)
    expect(fake.seen.first).to eq("esxcli x")
  end

  it "returns the no-output sentinel" do
    fake = FakeExecutor.new("   ")
    expect(Ssherlock::CheckRunner.run(fake, "x", server(false), false)).to eq("_no output_")
  end

  it "captures errors" do
    fake = FakeExecutor.new(raise: Exception.new("boom"))
    expect(Ssherlock::CheckRunner.run(fake, "x", server(false), false)).to eq("_error: boom_")
  end

  it "redacts when requested" do
    fake = FakeExecutor.new("password=hunter2")
    expect(Ssherlock::CheckRunner.run(fake, "x", server(false), true)).to eq("password=[REDACTED]")
  end
end
