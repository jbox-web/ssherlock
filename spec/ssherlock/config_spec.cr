require "../spec_helper"

class FakeResolver < Ssherlock::SshConfigResolver
  def initialize(@map : Hash(String, Ssherlock::ResolvedConfig))
  end

  def resolve(name : String) : Ssherlock::ResolvedConfig
    @map[name]? || Ssherlock::ResolvedConfig.new
  end
end

Spectator.describe Ssherlock::Config do
  let(loader) { Ssherlock::Preset::DirLoader.new(fixture_path("presets")) }
  let(config) { Ssherlock::Config.load(fixture_path("configs/mixed.yml"), loader) }

  it "reads run-level options" do
    expect(config.output_dir).to eq("/tmp/audit_test")
    expect(config.concurrency).to eq(4)
    expect(config.servers.size).to eq(2)
  end

  it "applies defaults to a bare server" do
    s = config.servers.find! { |x| x.label == "node1" }
    expect(s.target.user).to eq("root")
    expect(s.timeout).to eq(10)
    expect(s.wrap).to be_true
    expect(s.checks["cpu"].has_key?("lscpu")).to be_true
    expect(s.checks["cpu"].has_key?("extra_probe")).to be_true
  end

  it "lets a server override connection and preset" do
    s = config.servers.find! { |x| x.label == "node2" }
    expect(s.target.user).to eq("bar")
    expect(s.timeout).to eq(60)
    expect(s.wrap).to be_false
  end

  it "rejects an empty servers list" do
    raw = YAML.parse("servers: []")
    expect { Ssherlock::Config.new(raw, loader) }.to raise_error(Ssherlock::Error, /servers/)
  end

  it "rejects duplicate server labels" do
    raw = YAML.parse("defaults:\n  inherit: base\nservers:\n  - {host: h1, label: dup}\n  - {host: h2, label: dup}")
    expect { Ssherlock::Config.new(raw, loader) }.to raise_error(Ssherlock::Error, /duplicate/)
  end

  it "rejects a check with no command" do
    raw = YAML.parse("defaults:\n  inherit: nocmd\nservers:\n  - {host: h1, label: node1}")
    expect { Ssherlock::Config.new(raw, loader) }.to raise_error(Ssherlock::Error, /no command/)
  end

  it "restricts the fleet to a target matched by label" do
    config.restrict_to(["node2"])
    expect(config.servers.map(&.label)).to eq(["node2"])
  end

  it "matches a target by host as well as label" do
    config.restrict_to(["h1"])
    expect(config.servers.map(&.label)).to eq(["node1"])
  end

  it "keeps several targets and preserves fleet order" do
    config.restrict_to(["node2", "node1"])
    expect(config.servers.map(&.label)).to eq(["node1", "node2"])
  end

  it "keeps the whole fleet when no target is given" do
    config.restrict_to([] of String)
    expect(config.servers.size).to eq(2)
  end

  it "raises on an unknown target, listing known labels" do
    expect { config.restrict_to(["nope"]) }
      .to raise_error(Ssherlock::Error, /unknown target.*nope.*node1/m)
  end

  it "parses check metadata: category, severity, expected" do
    raw = YAML.parse(<<-YAML)
    presets:
      m:
        checks:
          ssh:
            root:
              category: security
              severity: high
              expected: "no"
              command: grep -i '^PermitRootLogin' /etc/ssh/sshd_config
          cpu:
            lscpu:
              category: inventory
              command: lscpu
    servers:
      - {host: h1, label: n1, inherit: m}
    YAML
    s = Ssherlock::Config.new(raw, loader).servers.first
    ctrl = s.checks["ssh"]["root"]
    expect(ctrl.category).to eq("security")
    expect(ctrl.severity).to eq("high")
    expect(ctrl.expected).to eq("no")
    inv = s.checks["cpu"]["lscpu"]
    expect(inv.category).to eq("inventory")
    expect(inv.severity).to be_nil
    expect(inv.expected).to be_nil
  end

  it "rejects an out-of-enum category" do
    raw = YAML.parse(<<-YAML)
    presets:
      m:
        checks:
          x:
            c: {category: nope, command: "true"}
    servers:
      - {host: h1, label: n1, inherit: m}
    YAML
    expect { Ssherlock::Config.new(raw, loader) }.to raise_error(Ssherlock::Error, /invalid category/)
  end

  it "rejects an out-of-enum severity" do
    raw = YAML.parse(<<-YAML)
    presets:
      m:
        checks:
          x:
            c: {category: security, severity: fatal, expected: "y", command: "true"}
    servers:
      - {host: h1, label: n1, inherit: m}
    YAML
    expect { Ssherlock::Config.new(raw, loader) }.to raise_error(Ssherlock::Error, /invalid severity/)
  end

  it "resolves a preset defined inline in the config's presets: block" do
    raw = YAML.parse(<<-YAML)
    presets:
      webnode:
        options: {wrap: true}
        checks:
          web:
            nginx:
              description: nginx version
              command: nginx -v
    servers:
      - {host: h1, label: n1, inherit: webnode}
    YAML
    config = Ssherlock::Config.new(raw, loader)
    s = config.servers.first
    expect(s.checks["web"].has_key?("nginx")).to be_true
    expect(s.wrap).to be_true
  end

  it "resolves presets_dir relative to the config file directory" do
    config = Ssherlock::Config.load(fixture_path("configs/ext_dir.yml"), loader)
    s = config.servers.first
    expect(s.checks["ext"].has_key?("marker")).to be_true
  end

  it "lets the --presets-dir override win over the presets_dir config key" do
    config = Ssherlock::Config.load(
      fixture_path("configs/ext_dir_bogus.yml"), loader,
      presets_dir: fixture_path("presets_ext"))
    s = config.servers.first
    expect(s.checks["ext"].has_key?("marker")).to be_true
  end

  it "gives inline presets precedence over the external dir and the base loader" do
    raw = YAML.parse(<<-YAML)
    presets:
      base:
        options: {wrap: true}
        checks:
          inline:
            win:
              command: echo inline
    servers:
      - {host: h1, label: n1, inherit: base}
    YAML
    config = Ssherlock::Config.new(raw, loader, presets_dir_override: fixture_path("presets_ext"))
    s = config.servers.first
    expect(s.checks["inline"].has_key?("win")).to be_true
    expect(s.checks.has_key?("cpu")).to be_false
    expect(s.checks.has_key?("fromdir")).to be_false
  end

  it "raises when presets_dir points at a missing directory" do
    raw = YAML.parse("servers:\n  - {host: h1, label: n1, inherit: base}")
    expect { Ssherlock::Config.new(raw, loader, presets_dir_override: "/no/such/dir") }
      .to raise_error(Ssherlock::Error, /presets_dir/)
  end

  it "resolves the target endpoint via ssh -G, config winning over resolution" do
    raw = YAML.parse(<<-YAML)
    servers:
      - host: digi.bastion
        label: b1
        inherit: base
        ssh:
          user: root
    YAML
    resolver = FakeResolver.new({
      "digi.bastion" => Ssherlock::ResolvedConfig.new(
        hostname: "193.116.173.79", user: "someoneelse", port: 22,
        identityfile: "~/.ssh/keys/my_key"),
    })
    config = Ssherlock::Config.new(raw, loader, resolver)
    server = config.servers.first
    expect(server.target.host).to eq("193.116.173.79")
    expect(server.target.user).to eq("root")
    expect(server.target.port).to eq(22)
    expect(server.target.key).to eq(Path["~/.ssh/keys/my_key"].expand(home: true).to_s)
    expect(server.target.name).to eq("digi.bastion")
  end
end
