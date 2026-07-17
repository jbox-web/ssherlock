module Ssherlock
  # Drives collection across the fleet with a bounded fiber pool and writes JSON.
  class Runner
    def initialize(@config : Config, @redact : Bool, @opener : Opener)
      @logger = Logger.build(@config.output_dir)
      @collector = Collector.new(@logger, @redact)
    end

    def call : Array(Collector::Envelope)
      FileUtils.mkdir_p(@config.output_dir)
      @logger.info("=== ssherlock — #{Time.local.to_s("%F")} ===")
      @logger.info("hosts: #{@config.servers.map(&.label).join(", ")}")

      # Fail fast rather than let every known_hosts-verifying host fail
      # authentication one by one with the same underlying cause.
      if @config.servers.any?(&.verify_host_key.==(:known_hosts))
        kh = File.expand_path("~/.ssh/known_hosts", home: true)
        raise Error.new("verify_host_key: known_hosts but no known_hosts file at #{kh}") unless File.exists?(kh)
      end

      results = collect_all
      write_all(results)
      ok = results.count { |r| r.error.nil? }
      @logger.info("done. #{ok}/#{@config.servers.size} hosts collected.")
      results
    end

    private def collect_all : Array(Collector::Envelope)
      queue = ::Channel(Server).new(@config.servers.size)
      @config.servers.each { |s| queue.send(s) }
      queue.close

      mutex = Mutex.new
      results = {} of String => Collector::Envelope
      pool = Math.min(@config.concurrency, @config.servers.size)
      done = ::Channel(Nil).new(pool)

      pool.times do
        spawn do
          begin
            loop do
              server = queue.receive?
              break if server.nil?
              env = @collector.collect(server, @opener)
              begin
                write_host(env)
              rescue ex
                @logger.error("[#{server.label}] failed to write #{env.label}.json: #{ex.message}")
              end
              mutex.synchronize { results[server.label] = env }
            end
          ensure
            done.send(nil)
          end
        end
      end
      pool.times { done.receive }

      @config.servers.compact_map { |s| results[s.label]? }
    end

    private def write_host(env : Collector::Envelope) : Nil
      File.write(File.join(@config.output_dir, "#{env.label}.json"), env.to_pretty_json)
    end

    private def write_all(results : Array(Collector::Envelope)) : Nil
      File.write(File.join(@config.output_dir, "all.json"), results.to_pretty_json)
    end
  end
end
