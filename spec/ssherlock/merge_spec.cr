require "../spec_helper"

Spectator.describe "Ssherlock.deep_merge" do
  def y(str)
    YAML.parse(str)
  end

  it "overrides scalars and merges nested hashes" do
    base = y("a: 1\nb:\n  c: 1\n  d: 1")
    over = y("b:\n  c: 2\n  e: 3")
    merged = Ssherlock.deep_merge(base, over)
    expect(merged["a"].as_i).to eq(1)
    expect(merged["b"]["c"].as_i).to eq(2)
    expect(merged["b"]["d"].as_i).to eq(1)
    expect(merged["b"]["e"].as_i).to eq(3)
  end

  it "knocks out a key when the override value is null" do
    base = y("checks:\n  cpu: keep\n  net: keep")
    over = y("checks:\n  net: ~")
    merged = Ssherlock.deep_merge(base, over)
    expect(merged["checks"].as_h.has_key?(YAML::Any.new("cpu"))).to be_true
    expect(merged["checks"].as_h.has_key?(YAML::Any.new("net"))).to be_false
  end
end
