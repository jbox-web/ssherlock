require "socket"

module Ssherlock
  # Opens authenticated SSH sessions (publickey/agent only), optionally jumping
  # through a bastion via a loopback local-forward built on direct_tcpip.
  #
  # Transient handshake failures (banner/socket errors) are retried; auth and
  # known_hosts failures are NOT retried — they are deterministic, and a host-key
  # mismatch must never be retried away.
  module SshSession
    # Connection attempts before giving up (1 try + 2 retries).
    CONNECT_ATTEMPTS = 3
    # Pause between attempts.
    RETRY_BACKOFF = 1.second
    # Bounds libssh2 blocking calls (auth, channel I/O) so a stalled peer fails
    # fast instead of hanging a fiber. The TCP connect is bounded separately by
    # `server.timeout`.
    SESSION_TIMEOUT_MS = 20_000

    def self.connect(server : Server, & : SSH2::Session ->)
      if b = server.bastion
        connect_via_bastion(server, b) { |session| yield session }
      else
        session = with_retry(server.label) { establish_direct(server) }
        begin
          yield session
        ensure
          session.disconnect rescue nil
        end
      end
    end

    # Establishes a direct session (socket + handshake + auth + host-key check).
    # Closes the socket if anything before a usable session fails.
    private def self.establish_direct(server : Server) : SSH2::Session
      t = server.target
      socket = TCPSocket.new(t.host, t.port, connect_timeout: server.timeout)
      begin
        session = SSH2::Session.new(socket)
        session.timeout = SESSION_TIMEOUT_MS
        Authenticator.authenticate(session, t)
        verify_host_key(session, server, t)
        session
      rescue ex
        socket.close rescue nil
        raise ex
      end
    end

    # The live resources of a bastion-forwarded connection: the target session to
    # use, plus the forward and bastion session to tear down afterwards.
    private record BastionConn, bastion : SSH2::Session, forward : TCPServer, session : SSH2::Session do
      def close : Nil
        session.disconnect rescue nil
        forward.close rescue nil
        bastion.disconnect rescue nil
      end
    end

    # Bastion path: connect to the jump host, stand up a loopback TCP forward
    # whose bytes are relayed through the jump host to the target via
    # direct_tcpip, then open the real session against 127.0.0.1:<port>.
    private def self.connect_via_bastion(server : Server, b : Endpoint, & : SSH2::Session ->)
      conn = with_retry(server.label) { establish_bastion(server, b) }
      begin
        yield conn.session
      ensure
        conn.close
      end
    end

    private def self.establish_bastion(server : Server, b : Endpoint) : BastionConn
      bastion_socket = TCPSocket.new(b.host, b.port, connect_timeout: server.timeout)
      bastion : SSH2::Session? = nil
      forward : TCPServer? = nil
      begin
        bastion = SSH2::Session.new(bastion_socket)
        bastion.timeout = SESSION_TIMEOUT_MS
        Authenticator.authenticate(bastion, b)
        verify_host_key(bastion, server, b)

        forward = TCPServer.new("127.0.0.1", 0)
        start_forward_relay(bastion, forward, server.target)

        target_session = SSH2::Session.connect("127.0.0.1", forward.local_address.port)
        target_session.timeout = SESSION_TIMEOUT_MS
        Authenticator.authenticate(target_session, server.target)
        # Verify against the real target alias (target.name), never 127.0.0.1 —
        # the loopback forward has no meaningful host key.
        verify_host_key(target_session, server, server.target)
        BastionConn.new(bastion, forward, target_session)
      rescue ex
        forward.try &.close rescue nil
        if b_session = bastion
          b_session.disconnect rescue nil
        else
          bastion_socket.close rescue nil
        end
        raise ex
      end
    end

    # Relays each accepted loopback connection through the bastion to the target
    # via direct_tcpip, in background fibers, until the forward is closed.
    private def self.start_forward_relay(bastion : SSH2::Session, forward : TCPServer, target : Endpoint) : Nil
      local_port = forward.local_address.port
      spawn do
        loop do
          client = forward.accept
          spawn do
            channel = bastion.direct_tcpip(target.host, target.port, "127.0.0.1", local_port)
            spawn do
              # Swallow the "Closed stream" both directions raise at teardown.
              IO.copy(client, channel) rescue nil
              channel.close rescue nil
            end
            IO.copy(channel, client)
          rescue
          ensure
            client.close rescue nil
          end
        end
      rescue IO::Error
        # forward was closed after the host's checks finished; stop accepting.
      end
    end

    # Runs the block, retrying transient connection/handshake failures (libssh2
    # banner/socket errors, socket I/O errors). Deterministic failures — auth and
    # known_hosts, which surface as `Ssherlock::Error` — are not retried.
    private def self.with_retry(label : String, & : -> T) : T forall T
      attempt = 0
      loop do
        attempt += 1
        return yield
      rescue ex : SSH2::SSH2Error | IO::Error
        raise ex if attempt >= CONNECT_ATTEMPTS
        sleep RETRY_BACKOFF
      end
    end

    # Enforces the strict known_hosts policy against endpoint.name (never a
    # loopback address) when the server opts into verify_host_key: :known_hosts.
    private def self.verify_host_key(session : SSH2::Session, server : Server, endpoint : Endpoint) : Nil
      return unless server.verify_host_key == :known_hosts

      verdict = session.verify_known_host(endpoint.name, endpoint.port)
      HostKeyPolicy.enforce(verdict, endpoint.name)
    end
  end
end
