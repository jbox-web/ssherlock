module Ssherlock
  # Strict known_hosts policy: only MATCH is accepted. Applied when
  # verify_host_key is :known_hosts.
  module HostKeyPolicy
    def self.enforce(verdict : LibSSH2::KnownHostCheck, name : String) : Nil
      case verdict
      when .match?
        nil
      when .mismatch?
        raise Error.new("host key mismatch for #{name}")
      when .notfound?
        raise Error.new("host key not found in known_hosts for #{name}")
      else
        raise Error.new("host key verification failed for #{name}")
      end
    end
  end
end
