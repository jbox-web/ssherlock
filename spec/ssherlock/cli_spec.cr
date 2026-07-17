require "../spec_helper"

Spectator.describe Ssherlock::CLI::RunCommand do
  it "reports a missing --config as a non-zero exit" do
    cmd = Ssherlock::CLI::RunCommand.new(["--config", "/does/not/exist.yml"] of String)
    expect(cmd.exit_code).to eq(1)
  end

  it "reports a malformed config as a non-zero exit instead of crashing" do
    file = File.tempfile("bad-config", ".yml") { |f| f.print("servers: [unclosed") }
    begin
      cmd = Ssherlock::CLI::RunCommand.new(["--config", file.path] of String)
      expect(cmd.exit_code).to eq(1)
    ensure
      file.delete
    end
  end

  it "rejects an unknown positional target as a non-zero exit" do
    file = File.tempfile("cfg", ".yml") do |f|
      f.print("servers:\n  - {host: h1, label: n1, inherit: linux}")
    end
    begin
      cmd = Ssherlock::CLI::RunCommand.new(["--config", file.path, "nope"] of String)
      expect(cmd.exit_code).to eq(1)
    ensure
      file.delete
    end
  end

  it "plumbs --presets-dir through and fails fast on a missing directory" do
    file = File.tempfile("cfg", ".yml") do |f|
      f.print("servers:\n  - {host: h1, label: n1, inherit: linux}")
    end
    begin
      cmd = Ssherlock::CLI::RunCommand.new(["--presets-dir", "/no/such/dir", "--config", file.path] of String)
      expect(cmd.exit_code).to eq(1)
    ensure
      file.delete
    end
  end
end

Spectator.describe Ssherlock::CLI::PresetsCommand do
  it "lists baked presets with a zero exit" do
    expect(Ssherlock::CLI::PresetsCommand.new([] of String).exit_code).to eq(0)
  end

  it "dumps a known preset with a zero exit" do
    expect(Ssherlock::CLI::PresetsCommand.new(["linux"] of String).exit_code).to eq(0)
  end

  it "reports an unknown preset as a non-zero exit" do
    expect(Ssherlock::CLI::PresetsCommand.new(["nope"] of String).exit_code).to eq(1)
  end
end

Spectator.describe Ssherlock::CLI::SkillCommand do
  it "prints the bundled skill with a zero exit" do
    expect(Ssherlock::CLI::SkillCommand.new([] of String).exit_code).to eq(0)
  end

  it "rejects an unknown action as a non-zero exit" do
    expect(Ssherlock::CLI::SkillCommand.new(["bogus"] of String).exit_code).to eq(1)
  end
end
