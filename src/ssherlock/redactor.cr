module Ssherlock
  # Masks common secret shapes in command output before serialisation.
  module Redactor
    PEM    = /-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----/m
    KV     = /\b(password|passwd|secret|token|api[_-]?key)\s*[=:]\s*\S+/i
    BEARER = /\b(Authorization:\s*Bearer)\s+\S+/i

    def self.call(text : String) : String
      text
        .gsub(PEM, "[REDACTED PRIVATE KEY]")
        .gsub(KV) { "#{$~[1]}=[REDACTED]" }
        .gsub(BEARER) { "#{$~[1]} [REDACTED]" }
    end
  end
end
