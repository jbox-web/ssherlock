require "../spec_helper"

class OkExecutor < Ssherlock::Executor
  def exec(cmd : String) : String
    "ok"
  end
end

class OkOpener < Ssherlock::Opener
  def open(server : Ssherlock::Server, &block : Ssherlock::Executor -> Nil) : Nil
    block.call(OkExecutor.new)
  end
end

Spectator.describe Ssherlock::Runner do
  it "writes per-host json and all.json" do
    dir = File.join(Dir.tempdir, "ae-run-#{Random.rand(100000)}")
    begin
      checks = {"cpu" => {"x" => Ssherlock::Check.new(command: "x", description: "probe")}}
      servers = [
        Ssherlock::Server.new(
          label: "n1",
          target: Ssherlock::Endpoint.new("h1", "h1", 22, "root", "/k"),
          bastion: nil,
          timeout: 10, cmd_timeout: 20, sudo: false, wrap: false,
          verify_host_key: :never,
          checks: checks,
        ),
      ]
      config = Ssherlock::Config.for_test(dir, 2, servers)

      results = Ssherlock::Runner.new(config, false, OkOpener.new).call

      expect(results.size).to eq(1)
      expect(File.exists?(File.join(dir, "n1.json"))).to be_true
      all = JSON.parse(File.read(File.join(dir, "all.json")))
      expect(all[0]["data"]["cpu"]["x"]["output"].as_s).to eq("ok")
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
