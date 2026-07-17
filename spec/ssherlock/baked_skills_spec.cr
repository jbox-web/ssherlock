require "../spec_helper"

Spectator.describe Ssherlock::BakedSkills do
  it "bakes the ssherlock-audit SKILL.md" do
    paths = Ssherlock::BakedSkills.files.map(&.path)
    expect(paths.any?(&.ends_with?("ssherlock-audit/SKILL.md"))).to be_true
  end

  it "carries the skill frontmatter" do
    md = Ssherlock::BakedSkills.files.map { |f| Ssherlock::BakedSkills.get(f.path).gets_to_end }.join
    expect(md.includes?("name: ssherlock-audit")).to be_true
  end

  it "installs the skill into a directory" do
    dir = File.tempname("skills")
    begin
      written = Ssherlock::BakedSkills.install(dir)
      expect(written.any?(&.ends_with?("ssherlock-audit/SKILL.md"))).to be_true
      expect(File.exists?(File.join(dir, "ssherlock-audit", "SKILL.md"))).to be_true
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "refuses to overwrite an existing file without force" do
    dir = File.tempname("skills")
    begin
      Ssherlock::BakedSkills.install(dir)
      expect { Ssherlock::BakedSkills.install(dir) }.to raise_error(Ssherlock::Error, /already exists/)
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "overwrites with force" do
    dir = File.tempname("skills")
    begin
      Ssherlock::BakedSkills.install(dir)
      expect(Ssherlock::BakedSkills.install(dir, force: true).empty?).to be_false
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
