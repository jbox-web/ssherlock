module Ssherlock
  # Collects one server into a JSON-serialisable envelope. The Opener yields the
  # Executor to run checks with (real SSH in production, a fake in tests) and
  # keeps it open for the whole scope, so the collector never touches the
  # network directly.
  class Collector
    alias Data = Hash(String, Hash(String, CheckResult))

    # One check's result plus its declarative metadata, serialised in a fixed
    # field order. Nil metadata fields are omitted from the JSON.
    struct CheckResult
      include JSON::Serializable
      getter category : String?
      getter severity : String?
      getter expected : String?
      getter description : String?
      getter output : String

      def initialize(@category, @severity, @expected, @description, @output)
      end
    end

    struct Envelope
      include JSON::Serializable
      getter label : String
      getter host : String
      getter error : String?
      getter collected_at : String
      getter data : Data

      def initialize(@label, @host, @error, @collected_at, @data)
      end
    end

    def initialize(@logger : Logger, @redact : Bool)
    end

    def collect(server : Server, opener : Opener) : Envelope
      @logger.info("[#{server.label}] connecting to #{server.target.host}...")
      data = Data.new
      opener.open(server) do |exec|
        data = run_checks(server, exec)
        nil
      end
      @logger.info("[#{server.label}] done")
      envelope(server, nil, data)
    rescue ex
      @logger.error("[#{server.label}] #{ex.message}")
      envelope(server, ex.message, Data.new)
    end

    private def run_checks(server : Server, exec : Executor) : Data
      data = Data.new
      server.checks.each do |section, checks|
        @logger.info("[#{server.label}] -> #{section}")
        section_map = Hash(String, CheckResult).new
        checks.each do |name, check|
          @logger.debug("[#{server.label}]   #{name}...")
          output = CheckRunner.run(exec, check.command, server, @redact)
          section_map[name] = CheckResult.new(
            check.category, check.severity, check.expected, check.description, output)
        end
        data[section] = section_map
      end
      data
    end

    private def envelope(server : Server, error : String?, data : Data) : Envelope
      Envelope.new(server.label, server.target.host, error, Time.local.to_s, data)
    end
  end
end
