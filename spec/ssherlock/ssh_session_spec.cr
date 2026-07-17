require "../spec_helper"

Spectator.describe Ssherlock::SshSession do
  def server(bastion : Ssherlock::Endpoint?)
    Ssherlock::Server.new(
      label: "l1",
      target: Ssherlock::Endpoint.new("h1", "h1", 22, "root", "/k"),
      bastion: bastion,
      timeout: 10, cmd_timeout: 20, sudo: false, wrap: true,
      verify_host_key: :never,
      checks: {} of String => Hash(String, Ssherlock::Check),
    )
  end

  it "carries the bastion endpoint through the server" do
    bastion = Ssherlock::Endpoint.new("jump", "jump", 22, "jumpuser", "/k")
    expect(server(bastion).bastion).to eq(bastion)
  end

  it "has no bastion for a direct connection" do
    expect(server(nil).bastion).to be_nil
  end
end
