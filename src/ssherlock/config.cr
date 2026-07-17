module Ssherlock
  # Loads and resolves one fleet config file into a list of Server structs.
  class Config
    getter output_dir : String
    getter concurrency : Int32
    getter servers : Array(Server)

    CATEGORIES = %w[inventory capacity security lifecycle availability observability]
    SEVERITIES = %w[low medium high]

    @defaults : YAML::Any
    @overrides : YAML::Any
    @loader : Preset::Loader

    def self.load(path : String, loader : Preset::Loader, presets_dir : String? = nil) : Config
      raise Error.new("config not found: #{path}") unless File.exists?(path)
      new(YAML.parse(File.read(path)), loader,
        presets_dir_override: presets_dir, config_dir: File.dirname(path))
    end

    # Test-only factory that bypasses YAML resolution.
    def self.for_test(output_dir : String, concurrency : Int32, servers : Array(Server)) : Config
      config = allocate
      config.init_test(output_dir, concurrency, servers)
      config
    end

    protected def init_test(@output_dir : String, @concurrency : Int32, @servers : Array(Server))
      @defaults = empty_hash
      @overrides = empty_hash
      @loader = Preset::DirLoader.new(".")
    end

    def initialize(raw : YAML::Any, base_loader : Preset::Loader,
                   @resolver : SshConfigResolver = SystemSshConfigResolver.new,
                   presets_dir_override : String? = nil, config_dir : String = ".")
      root = raw.as_h? || raise Error.new("config root must be a mapping")
      @defaults = root[YAML::Any.new("defaults")]? || empty_hash
      @overrides = root[YAML::Any.new("overrides")]? || empty_hash
      @loader = build_loader(root, base_loader, presets_dir_override, config_dir)

      @output_dir = (root[YAML::Any.new("output_dir")]?.try(&.as_s)) || "audit_#{Time.local.to_s("%F")}"
      @concurrency = ((root[YAML::Any.new("concurrency")]?.try(&.as_i)) || 6).clamp(1, 32)

      servers_node = root[YAML::Any.new("servers")]?.try(&.as_a?)
      raise Error.new("invalid config: servers must be a non-empty array") if servers_node.nil? || servers_node.empty?
      validate_servers!(servers_node)

      @servers = servers_node.map { |s| resolve_server(s) }
      ensure_unique_labels!
    end

    # Narrows the fleet to the given targets, each matched against a server's
    # label or host. Empty targets leave the fleet untouched; an unmatched
    # target raises. Order follows the config, not the target list.
    def restrict_to(targets : Array(String)) : Nil
      return if targets.empty?
      unknown = targets.reject { |t| @servers.any? { |s| s.label == t || s.target.name == t } }
      unless unknown.empty?
        raise Error.new("unknown target(s): #{unknown.join(", ")} — known labels: #{@servers.map(&.label).join(", ")}")
      end
      @servers = @servers.select { |s| targets.any? { |t| s.label == t || s.target.name == t } }
    end

    private def empty_hash : YAML::Any
      YAML::Any.new({} of YAML::Any => YAML::Any)
    end

    # Builds the preset resolution chain: inline `presets:` > external dir
    # (`--presets-dir` override or `presets_dir:` key) > baked catalogue. A name
    # is served by the first source that has it, so a shadowing preset must not
    # inherit the same name (the resolve cycle guard rejects that).
    private def build_loader(root : Hash(YAML::Any, YAML::Any), base_loader : Preset::Loader,
                             presets_dir_override : String?, config_dir : String) : Preset::Loader
      loaders = [] of Preset::Loader

      if inline = root[YAML::Any.new("presets")]?.try(&.as_h?)
        map = {} of String => YAML::Any
        inline.each { |name, node| map[name.as_s] = node }
        loaders << Preset::MapLoader.new(map)
      end

      dir = presets_dir_override || root[YAML::Any.new("presets_dir")]?.try(&.as_s)
      if dir
        resolved = Path[dir].absolute? ? dir : File.join(config_dir, dir)
        raise Error.new("presets_dir does not exist: #{resolved}") unless Dir.exists?(resolved)
        loaders << Preset::DirLoader.new(resolved)
      end

      loaders << base_loader
      loaders.size == 1 ? base_loader : Preset::ChainLoader.new(loaders)
    end

    private def validate_servers!(nodes : Array(YAML::Any)) : Nil
      nodes.each do |s|
        h = s.as_h? || raise Error.new("invalid config: each server must be a mapping")
        raise Error.new("invalid config: server missing host") unless h[YAML::Any.new("host")]?.try(&.as_s?)
        raise Error.new("invalid config: server missing label") unless h[YAML::Any.new("label")]?.try(&.as_s?)
      end
    end

    # Reads key `k` from the server's ssh: block; nil if absent.
    private def ssh_opt(conn : YAML::Any, k : String) : YAML::Any?
      conn["ssh"]?.try(&.as_h?).try(&.[YAML::Any.new(k)]?)
    end

    private def resolve_server(server : YAML::Any) : Server
      conn = Ssherlock.deep_merge(@defaults, server)
      preset_name = conn["inherit"]?.try(&.as_s) || raise Error.new("server #{conn["label"]?} has no preset (inherit)")
      preset = Preset.resolve(preset_name, @loader)
      override = @overrides.as_h[YAML::Any.new(preset_name)]? || empty_hash
      checks_any = Ssherlock.deep_merge(preset["checks"], override)

      ssh_config_on = ssh_opt(conn, "config").try(&.as_bool?) != false # default true
      resolver = ssh_config_on ? @resolver : PassthroughResolver.new

      name = conn["host"].as_s
      target = build_endpoint(name, conn, resolver)

      bastion_spec = ssh_opt(conn, "bastion").try(&.as_s)
      bastion = build_bastion(bastion_spec, conn, resolver)

      vhk = case ssh_opt(conn, "verify_host_key").try(&.as_s)
            when "known_hosts" then :known_hosts
            else                    :never
            end

      Server.new(
        label: conn["label"].as_s,
        target: target,
        bastion: bastion,
        timeout: ssh_opt(conn, "timeout").try(&.as_i?) || 10,
        cmd_timeout: conn["cmd_timeout"]?.try(&.as_i?) || 20,
        sudo: conn["sudo"]?.try(&.as_bool?) || false,
        wrap: preset["options"]["wrap"]?.try(&.as_bool?) || false,
        verify_host_key: vhk,
        checks: to_checks(checks_any),
      )
    end

    # Builds an Endpoint by layering: explicit ssh: config > ssh -G > default.
    private def build_endpoint(name : String, conn : YAML::Any, resolver : SshConfigResolver) : Endpoint
      r = resolver.resolve(name)
      user = ssh_opt(conn, "user").try(&.as_s) || r.user || "root"
      Endpoint.new(name, r.hostname || name, r.port || 22, user, resolve_key(conn, r))
    end

    # "none"/empty/nil bastion -> no bastion. "user@alias" splits the user; a bare
    # alias inherits nothing (ssh -G resolves user). Resolution follows the same rules.
    private def build_bastion(spec : String?, conn : YAML::Any, resolver : SshConfigResolver) : Endpoint?
      return nil if spec.nil?
      s = spec.strip
      return nil if s.empty? || s.downcase == "none"
      bname, buser_override = parse_bastion_spec(s)
      r = resolver.resolve(bname)
      user = resolve_bastion_user(buser_override, r, conn)
      Endpoint.new(bname, r.hostname || bname, r.port || 22, user, resolve_key(conn, r))
    end

    # Splits a bastion spec into {alias, explicit_user}. A bare alias (no "@")
    # carries no explicit user override.
    private def parse_bastion_spec(spec : String) : {String, String?}
      explicit_user, _, alias_name = spec.partition('@')
      return {explicit_user, nil} if alias_name.empty?
      {alias_name, explicit_user}
    end

    # Bastion user priority: "user@alias" spec > ssh -G > explicit ssh: user > default.
    private def resolve_bastion_user(explicit_spec_user : String?, r : ResolvedConfig, conn : YAML::Any) : String
      explicit_spec_user || r.user || ssh_opt(conn, "user").try(&.as_s) || "root"
    end

    # Key priority: explicit ssh: config > ssh -G > default, expanded to an absolute path.
    private def resolve_key(conn : YAML::Any, r : ResolvedConfig) : String
      key_raw = ssh_opt(conn, "key").try(&.as_s) || r.identityfile || "~/.ssh/id_rsa"
      expand_path(key_raw)
    end

    private def to_checks(node : YAML::Any) : Hash(String, Hash(String, Check))
      out = {} of String => Hash(String, Check)
      node.as_h.each do |section, checks|
        section_map = {} of String => Check
        checks.as_h.each do |name, spec|
          sh = spec.as_h
          command_node = sh[YAML::Any.new("command")]? || raise Error.new("check #{section.as_s}.#{name.as_s} has no command")
          category = sh[YAML::Any.new("category")]?.try(&.as_s)
          if category && !CATEGORIES.includes?(category)
            raise Error.new("check #{section.as_s}.#{name.as_s} has invalid category: #{category}")
          end
          severity = sh[YAML::Any.new("severity")]?.try(&.as_s)
          if severity && !SEVERITIES.includes?(severity)
            raise Error.new("check #{section.as_s}.#{name.as_s} has invalid severity: #{severity}")
          end
          section_map[name.as_s] = Check.new(
            command: command_node.as_s,
            description: sh[YAML::Any.new("description")]?.try(&.as_s),
            category: category,
            severity: severity,
            expected: sh[YAML::Any.new("expected")]?.try(&.as_s),
          )
        end
        out[section.as_s] = section_map
      end
      out
    end

    private def ensure_unique_labels! : Nil
      seen = Set(String).new
      dups = [] of String
      @servers.each do |s|
        dups << s.label unless seen.add?(s.label)
      end
      raise Error.new("duplicate server labels: #{dups.uniq.join(", ")}") unless dups.empty?
    end

    private def expand_path(path : String) : String
      path.starts_with?("~") ? Path[path].expand(home: true).to_s : path
    end
  end
end
