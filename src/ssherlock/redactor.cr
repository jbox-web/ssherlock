module Ssherlock
  # Masks common secret shapes in command output before serialisation.
  module Redactor
    PEM = /-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----/m

    # Words that mark a variable as secret-bearing. They are matched anywhere
    # inside the key, so both prefixes and suffixes are covered
    # (MYSQL_PASSWORD, PASSWORD_FILE, APP__DB_PASSWORD).
    SECRET_WORD = "password|passwd|pwd|passphrase|secret|credentials?|token|dsn|api[_-]?key|private[_-]?key"

    # Characters a variable name may be built from. The lookbehind stops the
    # match from starting mid-key, so the whole name is captured and kept.
    KEY_CHAR = "[A-Za-z0-9_.-]"

    # Only "=" and ":" count as separators: a bare space would swallow
    # sshd_config directives ("PasswordAuthentication no") and commented redis
    # settings ("# requirepass foobared"), which must stay readable.
    KV = /(?<!#{KEY_CHAR})(#{KEY_CHAR}*(?:#{SECRET_WORD})#{KEY_CHAR}*)(\s*[=:]\s*)("[^"]*"|'[^']*'|\S+)/i

    # Keys that merely mention a secret without carrying one: shell
    # working-directory variables, and policy/boolean settings whose value is
    # itself an audit finding ("password_required=yes").
    KEEP = /\A(?:old)?pwd\z|(?:required|authentication|auth|enabled|disabled|policy|prompt)\z/i

    BEARER = /\b(Authorization:\s*Bearer)\s+\S+/i

    def self.call(text : String) : String
      text
        .gsub(PEM, "[REDACTED PRIVATE KEY]")
        .gsub(KV) do |whole, match|
          key, separator = match[1], match[2]
          key.matches?(KEEP) ? whole : "#{key}#{separator}[REDACTED]"
        end
        .gsub(BEARER) { "#{$~[1]} [REDACTED]" }
    end
  end
end
