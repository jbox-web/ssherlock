require "../spec_helper"

Spectator.describe Ssherlock::BakedPresets do
  it "resolves proxmox with wrap true and cluster checks" do
    p = Ssherlock::Preset.resolve("proxmox", Ssherlock::BakedPresets.loader)
    expect(p["options"]["wrap"].as_bool).to be_true
    expect(p["checks"]["cluster"].as_h.has_key?(YAML::Any.new("pvecm_status"))).to be_true
  end

  it "resolves vmware with wrap false" do
    p = Ssherlock::Preset.resolve("vmware", Ssherlock::BakedPresets.loader)
    expect(p["options"]["wrap"].as_bool).to be_false
  end

  it "resolves linux-full inheriting linux plus posture" do
    p = Ssherlock::Preset.resolve("linux-full", Ssherlock::BakedPresets.loader)
    expect(p["checks"]["services"].as_h.has_key?(YAML::Any.new("packages"))).to be_true
    expect(p["checks"]["ssh"].as_h.has_key?(YAML::Any.new("permit_root_login"))).to be_true
  end

  it "raises on unknown preset" do
    expect { Ssherlock::Preset.resolve("nope", Ssherlock::BakedPresets.loader) }.to raise_error(Ssherlock::Error, /unknown preset/)
  end

  it "enumerates the baked preset names" do
    names = Ssherlock::BakedPresets.names
    expect(names).to contain("linux", "linux-full", "proxmox", "vmware")
    expect(names).to eq(names.sort)
  end

  it "dumps a resolved preset as reparseable YAML" do
    dump = Ssherlock::Preset.resolve("linux", Ssherlock::BakedPresets.loader).to_yaml
    parsed = YAML.parse(dump)
    expect(parsed["checks"]["cpu"].as_h.has_key?(YAML::Any.new("lscpu"))).to be_true
  end
end
