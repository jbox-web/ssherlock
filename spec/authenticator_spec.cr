require "./spec_helper"

# A stand-in for SSH2::Session exposing only what the authenticator touches.
class FakeSession
  property? agent_ok = false
  property? key_ok = false
  getter? authenticated = false
  getter calls = [] of String

  def login_with_agent(user : String)
    @calls << "agent"
    raise "agent auth failed" unless @agent_ok
    @authenticated = true
  end

  def login_with_pubkey(user : String, priv : String, pub : String)
    @calls << "key"
    raise "no such file" unless @key_ok
    @authenticated = true
  end
end

private def endpoint
  Ssherlock::Endpoint.new("h", "h", 22, "root", "/tmp/nope")
end

Spectator.describe Ssherlock::Authenticator do
  it "succeeds via the agent and does not try the key" do
    s = FakeSession.new; s.agent_ok = true
    Ssherlock::Authenticator.authenticate(s, endpoint)
    expect(s.authenticated?).to be_true
    expect(s.calls).to eq(["agent"])
  end

  it "falls back to the key when the agent fails" do
    s = FakeSession.new; s.key_ok = true
    Ssherlock::Authenticator.authenticate(s, endpoint)
    expect(s.authenticated?).to be_true
    expect(s.calls).to eq(["agent", "key"])
  end

  it "raises Ssherlock::Error when both fail" do
    s = FakeSession.new
    expect { Ssherlock::Authenticator.authenticate(s, endpoint) }
      .to raise_error(Ssherlock::Error, /authentication failed/)
  end
end
