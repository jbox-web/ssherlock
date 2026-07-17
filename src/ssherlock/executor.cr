module Ssherlock
  # Runs a single command and returns its combined output. The SSH-backed
  # implementation is used in production; specs inject a fake.
  abstract class Executor
    abstract def exec(cmd : String) : String
  end

  # Executes commands over an open ssh2 session.
  class SshExecutor < Executor
    def initialize(@session : SSH2::Session)
    end

    def exec(cmd : String) : String
      output = IO::Memory.new
      @session.open_session do |channel|
        channel.command(cmd)
        IO.copy(channel, output)
      end
      output.to_s
    end
  end

  # Opens the per-host resource that checks run against and yields an Executor
  # bound to it, keeping it open for the whole block. Specs inject a fake. The
  # captured-block form (not `yield`) is required so the collector can dispatch
  # polymorphically on an `Opener` reference — verified to compile in the POC.
  abstract class Opener
    abstract def open(server : Server, &block : Executor -> Nil) : Nil
  end

  # Production opener: an authenticated SSH session (publickey, bastion-aware).
  class SshOpener < Opener
    def open(server : Server, &block : Executor -> Nil) : Nil
      SshSession.connect(server) do |session|
        block.call(SshExecutor.new(session))
      end
    end
  end
end
