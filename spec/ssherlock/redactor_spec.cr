require "../spec_helper"

Spectator.describe Ssherlock::Redactor do
  it "masks key=value secrets" do
    expect(Ssherlock::Redactor.call("password=hunter2 foo")).to eq("password=[REDACTED] foo")
  end

  # The key name itself is audit-relevant ("MYSQL_PASSWORD is set" is a
  # finding); only the value is masked, and the original separator is kept.
  describe "prefixed and suffixed keys" do
    it "masks a prefixed key" do
      expect(Ssherlock::Redactor.call("MYSQL_PASSWORD=hunter2")).to eq("MYSQL_PASSWORD=[REDACTED]")
    end

    it "masks a colon-separated key and preserves the separator" do
      expect(Ssherlock::Redactor.call("DB_PASSWORD: hunter2")).to eq("DB_PASSWORD: [REDACTED]")
    end

    it "masks REDIS_PASSWORD" do
      expect(Ssherlock::Redactor.call("REDIS_PASSWORD=x")).to eq("REDIS_PASSWORD=[REDACTED]")
    end

    it "masks a PWD-suffixed key" do
      expect(Ssherlock::Redactor.call("SALT_MASTER_PWD=x")).to eq("SALT_MASTER_PWD=[REDACTED]")
    end

    it "masks a DSN connection string" do
      expect(Ssherlock::Redactor.call("DATABASE_DSN=mysql://u:p@h/d")).to eq("DATABASE_DSN=[REDACTED]")
    end

    it "masks MY_SECRET" do
      expect(Ssherlock::Redactor.call("MY_SECRET=x")).to eq("MY_SECRET=[REDACTED]")
    end

    it "masks api_key" do
      expect(Ssherlock::Redactor.call("api_key=abc")).to eq("api_key=[REDACTED]")
    end

    it "masks a suffixed key" do
      expect(Ssherlock::Redactor.call("PASSWORD_FILE=/run/secrets/db")).to eq("PASSWORD_FILE=[REDACTED]")
    end

    it "masks a key carrying both prefix and suffix" do
      expect(Ssherlock::Redactor.call("APP__DB_PASSWORD_2=x")).to eq("APP__DB_PASSWORD_2=[REDACTED]")
    end
  end

  describe "additional secret keywords" do
    it "masks CREDENTIALS" do
      expect(Ssherlock::Redactor.call("AWS_CREDENTIALS=abc")).to eq("AWS_CREDENTIALS=[REDACTED]")
    end

    it "masks CREDENTIAL" do
      expect(Ssherlock::Redactor.call("VAULT_CREDENTIAL=abc")).to eq("VAULT_CREDENTIAL=[REDACTED]")
    end

    it "masks PRIVATE_KEY" do
      expect(Ssherlock::Redactor.call("TLS_PRIVATE_KEY=abc")).to eq("TLS_PRIVATE_KEY=[REDACTED]")
    end

    it "masks PASSPHRASE" do
      expect(Ssherlock::Redactor.call("GPG_PASSPHRASE=abc")).to eq("GPG_PASSPHRASE=[REDACTED]")
    end

    it "masks AUTH_TOKEN" do
      expect(Ssherlock::Redactor.call("AUTH_TOKEN=abc")).to eq("AUTH_TOKEN=[REDACTED]")
    end
  end

  describe "quoted values" do
    it "masks a double-quoted value including its spaces" do
      expect(Ssherlock::Redactor.call(%(PASSWORD="hunter 2" tail))).to eq("PASSWORD=[REDACTED] tail")
    end

    it "masks a single-quoted value including its spaces" do
      expect(Ssherlock::Redactor.call(%(PASSWORD='hunter 2' tail))).to eq("PASSWORD=[REDACTED] tail")
    end
  end

  describe "false positives" do
    it "leaves a boolean policy flag readable" do
      expect(Ssherlock::Redactor.call("password_required=yes")).to eq("password_required=yes")
    end

    it "leaves the sshd_config PasswordAuthentication directive readable" do
      expect(Ssherlock::Redactor.call("PasswordAuthentication no")).to eq("PasswordAuthentication no")
    end

    it "leaves a commented redis requirepass directive readable" do
      expect(Ssherlock::Redactor.call("# requirepass foobared")).to eq("# requirepass foobared")
    end

    it "leaves the shell working-directory variables readable" do
      expect(Ssherlock::Redactor.call("PWD=/root OLDPWD=/tmp")).to eq("PWD=/root OLDPWD=/tmp")
    end
  end

  it "masks a Bearer authorization header" do
    expect(Ssherlock::Redactor.call("Authorization: Bearer abc123")).to eq("Authorization: Bearer [REDACTED]")
  end

  it "masks PEM private key blocks" do
    pem = "-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----"
    expect(Ssherlock::Redactor.call(pem)).to eq("[REDACTED PRIVATE KEY]")
  end

  it "leaves clean text untouched" do
    expect(Ssherlock::Redactor.call("all good")).to eq("all good")
  end
end
