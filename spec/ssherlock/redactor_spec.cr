require "../spec_helper"

Spectator.describe Ssherlock::Redactor do
  it "masks key=value secrets" do
    expect(Ssherlock::Redactor.call("password=hunter2 foo")).to eq("password=[REDACTED] foo")
  end

  it "masks PEM private key blocks" do
    pem = "-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----"
    expect(Ssherlock::Redactor.call(pem)).to eq("[REDACTED PRIVATE KEY]")
  end

  it "leaves clean text untouched" do
    expect(Ssherlock::Redactor.call("all good")).to eq("all good")
  end
end
