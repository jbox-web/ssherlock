require "../spec_helper"

Spectator.describe Ssherlock::Logger do
  it "writes plain lines to collect.log and creates the dir" do
    dir = File.join(Dir.tempdir, "ae-log-#{Random.rand(100000)}", "sub")
    begin
      logger = Ssherlock::Logger.build(dir)
      logger.info("hello world")
      log = File.read(File.join(dir, "collect.log"))
      expect(log).to contain("INFO")
      expect(log).to contain("hello world")
      expect(log).to_not contain("\e[")
    ensure
      FileUtils.rm_rf(File.dirname(dir))
    end
  end
end
