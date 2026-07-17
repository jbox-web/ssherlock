module Ssherlock
  # Authenticates a session like a real ssh client: agent first, key file as a
  # fallback. `session` is duck-typed so it can be unit-tested with a double.
  module Authenticator
    def self.authenticate(session, endpoint : Endpoint) : Nil
      return if try(session) { session.login_with_agent(endpoint.user) }
      return if try(session) { session.login_with_pubkey(endpoint.user, endpoint.key, "#{endpoint.key}.pub") }
      raise Error.new("authentication failed for #{endpoint.name}")
    end

    # Runs one auth attempt, swallowing its error, and reports whether it authenticated.
    private def self.try(session, &) : Bool
      yield
      session.authenticated?
    rescue
      false
    end
  end
end
