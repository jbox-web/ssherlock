require "file_utils"

module Ssherlock
  # Dual logger: coloured stdout + plain file (collect.log) in the output dir.
  class Logger
    ANSI = {
      "DEBUG" => "\e[36m", "INFO" => "\e[32m",
      "WARN" => "\e[33m", "ERROR" => "\e[31m",
    }
    RESET = "\e[0m"

    def self.build(output_dir : String) : Logger
      FileUtils.mkdir_p(output_dir)
      new(File.new(File.join(output_dir, "collect.log"), "a"))
    end

    def initialize(@file : File)
      @mutex = Mutex.new
    end

    {% for level in %w[debug info warn error] %}
      def {{level.id}}(msg : String) : Nil
        emit({{level.upcase}}, msg)
      end
    {% end %}

    private def emit(level : String, msg : String) : Nil
      @mutex.synchronize do
        ts = Time.local.to_s("%H:%M:%S")
        @file.puts("[#{ts}] #{level.ljust(5)} — #{msg}")
        @file.flush
        color = ANSI[level]? || RESET
        STDOUT.puts("\e[90m[#{ts}]#{RESET} #{color}#{level.ljust(5)}#{RESET} #{color}#{msg}#{RESET}")
      end
    end
  end
end
