require "yaml"
require "json"
require "socket"
require "file_utils"
require "ssh2"
require "admiral"
require "baked_file_system"
require "crystal-env"

require "./ssherlock/error"
require "./ssherlock/helpers"
require "./ssherlock/merge"
require "./ssherlock/check"
require "./ssherlock/endpoint"
require "./ssherlock/authenticator"
require "./ssherlock/server"
require "./ssherlock/host_key_policy"
require "./ssherlock/preset"
require "./ssherlock/baked_presets"
require "./ssherlock/config"
require "./ssherlock/redactor"
require "./ssherlock/ssh_config_resolver"
require "./ssherlock/ssh_session"
require "./ssherlock/executor"
require "./ssherlock/check_runner"
require "./ssherlock/logger"
require "./ssherlock/collector"
require "./ssherlock/runner"
require "./ssherlock/licenses"
require "./ssherlock/baked_skills"
require "./ssherlock/cli"

unless Crystal.env.test?
  begin
    Ssherlock::CLI.run
  rescue e : Exception
    STDERR.puts e.message
    exit 1
  end
end
