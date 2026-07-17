require "./spec_helper"

Spectator.describe Ssherlock::SshConfigResolver do
  describe ".parse" do
    it "extracts hostname, user, port and the first identityfile" do
      output = <<-OUT
      host digi.bastion
      hostname 193.116.173.79
      user root
      port 22
      identityfile ~/.ssh/keys/my_key
      identityfile ~/.ssh/id_rsa
      OUT
      resolved = Ssherlock::SshConfigResolver.parse(output)
      expect(resolved.hostname).to eq("193.116.173.79")
      expect(resolved.user).to eq("root")
      expect(resolved.port).to eq(22)
      expect(resolved.identityfile).to eq("~/.ssh/keys/my_key")
    end

    it "returns all-nil when keys are absent" do
      resolved = Ssherlock::SshConfigResolver.parse("host x\n")
      expect(resolved.hostname).to be_nil
      expect(resolved.user).to be_nil
      expect(resolved.port).to be_nil
      expect(resolved.identityfile).to be_nil
    end
  end
end
