module Ssherlock
  # A resolved SSH connection endpoint (target or bastion). `name` is the original
  # alias (used for known_hosts and logs); `host` is the resolved address used for
  # the actual TCP connection / direct_tcpip.
  struct Endpoint
    getter name : String
    getter host : String
    getter port : Int32
    getter user : String
    getter key : String

    def initialize(@name, @host, @port, @user, @key)
    end
  end
end
