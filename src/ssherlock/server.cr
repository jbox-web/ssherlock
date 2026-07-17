module Ssherlock
  # A resolved target: connection endpoints plus the check catalogue to run.
  struct Server
    getter label : String
    getter target : Endpoint
    getter bastion : Endpoint?
    getter timeout : Int32
    getter cmd_timeout : Int32
    getter sudo : Bool
    getter wrap : Bool
    getter verify_host_key : Symbol
    getter checks : Hash(String, Hash(String, Check))

    def initialize(@label, @target, @bastion, @timeout, @cmd_timeout, @sudo, @wrap,
                   @verify_host_key, @checks)
    end
  end
end
