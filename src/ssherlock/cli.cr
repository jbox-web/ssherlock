module Ssherlock
  # Command-line front end: `ssherlock run <config.yml> [--redact]`.
  class CLI < Admiral::Command
    define_version Ssherlock.version
    define_help description: "ssherlock — read-only SSH audit collector"

    # Named `RunCommand`, not `Run`: admiral's `Admiral::Command` defines a
    # private `Run` module used internally by its `inherited`/`finished` macro
    # chain (`include Run` gets injected into any command with subcommands).
    # A nested class literally named `Run` shadows that lookup and breaks
    # compilation ("Run is not a module, it's a class").
    class RunCommand < Admiral::Command
      define_help description: "Collect audit data; positional args target specific machines by label or host"
      define_flag redact : Bool, long: "redact", default: false, description: "Mask secrets in output"                                # ameba:disable Lint/UselessAssign
      define_flag presets_dir : String, long: "presets-dir", default: "", description: "Directory of user preset YAML files"          # ameba:disable Lint/UselessAssign
      define_flag config : String, long: "config", short: "c", default: "ssherlock.yml", description: "Path to the fleet config YAML" # ameba:disable Lint/UselessAssign

      def exit_code : Int32
        Ssherlock.run(flags.config, redact: flags.redact,
          presets_dir: flags.presets_dir.presence, targets: arguments.rest)
        0
      rescue ex : Exception
        STDERR.puts "Error: #{ex.message}"
        1
      end

      def run
        exit(exit_code)
      end
    end

    # Prints the third-party + project license texts baked into the binary,
    # required for the statically-linked dependencies of the release build.
    class LicensesCommand < Admiral::Command
      define_help description: "Print the bundled third-party license texts"

      def run
        Ssherlock::Licenses.files.each do |file|
          puts "===== #{file.path} ====="
          puts file.gets_to_end
        end
      end
    end

    # Lists the baked preset names, or dumps one preset's resolved catalogue
    # (after `inherit:`) as YAML — directly pasteable into a `presets:` or
    # `overrides:` block. Reads only the baked catalogue; no config file needed.
    class PresetsCommand < Admiral::Command
      define_help description: "List baked presets, or dump one resolved as YAML"
      define_argument name : String, description: "Preset to dump; omit to list all"

      def exit_code : Int32
        name = arguments.name
        if name && !name.empty?
          puts Ssherlock::Preset.dump(name, BakedPresets.loader)
        else
          BakedPresets.names.each { |n| puts n }
        end
        0
      rescue ex : Exception
        STDERR.puts "Error: #{ex.message}"
        1
      end

      def run
        exit(exit_code)
      end
    end

    # Prints the ssherlock-audit skill baked into the binary, or installs it into
    # a skills directory Claude Code loads (`./.claude/skills`, or `~/.claude/skills`
    # with `--global`). Install refuses to clobber an existing file without `--force`.
    # The binary carries the analysis half; it does not run it — an LLM does.
    class SkillCommand < Admiral::Command
      define_help description: "Print the bundled ssherlock-audit skill, or install it"
      define_flag global : Bool, description: "Install into ~/.claude/skills instead of ./.claude/skills", default: false # ameba:disable Lint/UselessAssign
      define_flag force : Bool, description: "Overwrite existing skill files on install", default: false                  # ameba:disable Lint/UselessAssign
      define_argument action : String, description: "'install' to write the skill; omit to print it"

      def exit_code : Int32
        action = arguments.action
        if action == "install"
          base = flags.global ? File.expand_path(File.join("~", ".claude", "skills"), home: true) : File.join(".claude", "skills")
          BakedSkills.install(base, flags.force).each { |path| puts "wrote #{path}" }
        elsif action.nil? || action.empty?
          BakedSkills.print(STDOUT)
        else
          STDERR.puts "Error: unknown action '#{action}' (expected 'install', or omit to print)"
          return 1
        end
        0
      rescue ex : Exception
        STDERR.puts "Error: #{ex.message}"
        1
      end

      def run
        exit(exit_code)
      end
    end

    register_sub_command run, RunCommand, description: "Collect audit data"
    register_sub_command presets, PresetsCommand, description: "List or dump baked presets"
    register_sub_command licenses, LicensesCommand, description: "Print bundled licenses"
    register_sub_command skill, SkillCommand, description: "Print or install the ssherlock-audit skill"

    def run
      puts help
    end
  end
end
