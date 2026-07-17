module Ssherlock
  # The subset of `ssh -G` output we care about. Nil means "not provided".
  struct ResolvedConfig
    getter hostname : String?
    getter user : String?
    getter port : Int32?
    getter identityfile : String?

    def initialize(@hostname = nil, @user = nil, @port = nil, @identityfile = nil)
    end
  end

  # Resolves a host alias the way the ssh client would. Injectable so config
  # resolution is unit-tested against a fake.
  abstract class SshConfigResolver
    abstract def resolve(name : String) : ResolvedConfig

    # Parses `ssh -G` output: lowercase "key value" lines, one per line. Keeps the
    # first identityfile (ssh lists them in priority order).
    def self.parse(output : String) : ResolvedConfig
      hostname = user = identityfile = nil
      port = nil
      output.each_line do |line|
        key, _, value = line.strip.partition(' ')
        value = value.strip
        next if value.empty?
        case key.downcase
        when "hostname"     then hostname = value
        when "user"         then user = value
        when "port"         then port = value.to_i?
        when "identityfile" then identityfile ||= value
        end
      end
      ResolvedConfig.new(hostname, user, port, identityfile)
    end
  end

  # Real resolver: shells out to `ssh -G <name>`. Any failure (ssh missing,
  # non-zero exit) yields an all-nil ResolvedConfig so the caller falls back to
  # the raw config values.
  class SystemSshConfigResolver < SshConfigResolver
    def resolve(name : String) : ResolvedConfig
      buffer = IO::Memory.new
      status = Process.run("ssh", ["-G", name], output: buffer, error: Process::Redirect::Close)
      return ResolvedConfig.new unless status.success?
      SshConfigResolver.parse(buffer.to_s)
    rescue
      ResolvedConfig.new
    end
  end

  # Passthrough resolver: never resolves anything. Used when ssh.config is off.
  class PassthroughResolver < SshConfigResolver
    def resolve(name : String) : ResolvedConfig
      ResolvedConfig.new
    end
  end
end
