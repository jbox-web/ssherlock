require "../spec_helper"

Spectator.describe "Ssherlock version" do
  it "exposes a semantic version string" do
    expect(Ssherlock::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it "builds a version-with-ref string" do
    expect(Ssherlock.version).to contain(Ssherlock::VERSION)
  end
end
