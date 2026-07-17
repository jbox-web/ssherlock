module Ssherlock
  VERSION = {{ `shards version #{__DIR__}`.chomp.stringify }}
  GIT_REF = {{ `git log -n 1 --format="%H" 2>/dev/null | head -c 8 || echo unknown`.chomp.stringify }}

  def self.version : String
    "#{VERSION} (#{GIT_REF})"
  end

  def self.run(path : String, loader : Preset::Loader = BakedPresets.loader,
               redact : Bool = false, presets_dir : String? = nil,
               targets : Array(String) = [] of String) : Array(Collector::Envelope)
    config = Config.load(path, loader, presets_dir)
    config.restrict_to(targets)
    Runner.new(config, redact, SshOpener.new).call
  end
end
