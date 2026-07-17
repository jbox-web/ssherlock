require "../spec_helper"

Spectator.describe Ssherlock::Preset do
  let(loader) { Ssherlock::Preset::DirLoader.new(fixture_path("presets")) }

  it "loads a leaf preset" do
    p = Ssherlock::Preset.resolve("base", loader)
    expect(p["options"]["wrap"].as_bool).to be_true
    expect(p["checks"]["cpu"]["lscpu"]["command"].as_s).to eq("lscpu\n")
  end

  it "merges an inherited preset and honours knockout" do
    p = Ssherlock::Preset.resolve("child", loader)
    expect(p["options"]["wrap"].as_bool).to be_false
    checks = p["checks"]["cpu"].as_h
    expect(checks.has_key?(YAML::Any.new("lscpu"))).to be_true
    expect(checks.has_key?(YAML::Any.new("extra"))).to be_true
    expect(p["checks"]["net"].as_h.has_key?(YAML::Any.new("routes"))).to be_false
  end

  it "raises on unknown preset" do
    expect { Ssherlock::Preset.resolve("nope", loader) }.to raise_error(Ssherlock::Error, /unknown preset/)
  end

  it "dumps a resolved preset as YAML with trailing newlines stripped from commands" do
    dump = Ssherlock::Preset.dump("base", loader)
    expect(YAML.parse(dump)["checks"]["cpu"]["lscpu"]["command"].as_s).to eq("lscpu")
    expect(dump).not_to contain("'lscpu\n")
  end
end

Spectator.describe Ssherlock::Preset::MapLoader do
  let(map) do
    Ssherlock::Preset::MapLoader.new({
      "inline" => YAML.parse("options: {wrap: true}\nchecks: {cpu: {n: {command: nproc}}}"),
    } of String => YAML::Any)
  end

  it "serves an inline preset by name" do
    content = map.read?("inline")
    expect(content).not_to be_nil
    expect(YAML.parse(content.as(String))["checks"]["cpu"]["n"]["command"].as_s).to eq("nproc")
  end

  it "returns nil for an unknown name" do
    expect(map.read?("absent")).to be_nil
  end
end

Spectator.describe Ssherlock::Preset::ChainLoader do
  let(dir) { Ssherlock::Preset::DirLoader.new(fixture_path("presets")) }
  let(inline) do
    Ssherlock::Preset::MapLoader.new({
      "base" => YAML.parse("options: {wrap: false}\nchecks: {marker: {m: {command: inline}}}"),
    } of String => YAML::Any)
  end

  it "returns the first source that resolves a name" do
    chain = Ssherlock::Preset::ChainLoader.new([inline, dir] of Ssherlock::Preset::Loader)
    expect(YAML.parse(chain.read("base"))["checks"]["marker"]["m"]["command"].as_s).to eq("inline")
  end

  it "falls through to a later source" do
    chain = Ssherlock::Preset::ChainLoader.new([inline, dir] of Ssherlock::Preset::Loader)
    expect(YAML.parse(chain.read("child"))["checks"]["cpu"]["extra"]["command"].as_s).to eq("nproc\n")
  end

  it "raises unknown preset when no source resolves" do
    chain = Ssherlock::Preset::ChainLoader.new([dir] of Ssherlock::Preset::Loader)
    expect { chain.read("nope") }.to raise_error(Ssherlock::Error, /unknown preset/)
  end
end
