module Ssherlock
  class TimeoutError < Exception
  end

  # Runs one command through an Executor, wrapping and guarding it.
  module CheckRunner
    def self.run(exec : Executor, cmd : String, server : Server, redact : Bool) : String
      wrapped = wrap(cmd, server)
      output =
        begin
          run_with_timeout(exec, wrapped, server.cmd_timeout + 5)
        rescue TimeoutError
          return "_timeout (> #{server.cmd_timeout}s)_"
        rescue ex
          return "_error: #{ex.message}_"
        end

      output = output.strip
      output = "_no output_" if output.empty?
      redact ? Redactor.call(output) : output
    end

    # Ruby-side guard: a frozen SSH channel cannot stall the whole run.
    private def self.run_with_timeout(exec : Executor, cmd : String, seconds : Int32) : String
      chan = ::Channel(String).new(1)
      err = ::Channel(Exception).new(1)
      spawn do
        begin
          chan.send(exec.exec(cmd))
        rescue ex
          err.send(ex)
        end
      end

      select
      when result = chan.receive
        result
      when ex = err.receive
        raise ex
      when timeout(seconds.seconds)
        raise TimeoutError.new
      end
    end

    def self.wrap(cmd : String, server : Server) : String
      return cmd unless server.wrap
      base = "timeout #{server.cmd_timeout} sh -c #{Process.quote(cmd)}"
      server.sudo ? "sudo #{base}" : base
    end
  end
end
