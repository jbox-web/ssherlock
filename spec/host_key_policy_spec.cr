require "./spec_helper"

Spectator.describe Ssherlock::HostKeyPolicy do
  it "passes on MATCH" do
    Ssherlock::HostKeyPolicy.enforce(LibSSH2::KnownHostCheck::MATCH, "h")
  end

  it "raises on MISMATCH, NOTFOUND and FAILURE" do
    {LibSSH2::KnownHostCheck::MISMATCH,
     LibSSH2::KnownHostCheck::NOTFOUND,
     LibSSH2::KnownHostCheck::FAILURE}.each do |verdict|
      expect { Ssherlock::HostKeyPolicy.enforce(verdict, "h") }
        .to raise_error(Ssherlock::Error, /host key/)
    end
  end
end
