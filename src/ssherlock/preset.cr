module Ssherlock
  # Loads a check catalogue and resolves its `inherit:` chain (child overrides
  # parent; a null value knocks a check out).
  module Preset
    # A source of preset YAML by name. Concrete loaders read from a directory
    # (tests) or from the baked-in presets (production).
    abstract class Loader
      # Returns the raw preset YAML for `name`, or nil when this source has no
      # such preset. Concrete loaders implement this; `read` layers on the
      # raising behaviour shared by every source, so `ChainLoader` can probe a
      # source without a rescue.
      abstract def read?(name : String) : String?

      def read(name : String) : String
        read?(name) || raise Error.new("unknown preset: #{name}")
      end
    end

    # Reads `<dir>/<name>.yml` from disk.
    class DirLoader < Loader
      def initialize(@dir : String)
      end

      def read?(name : String) : String?
        file = File.join(@dir, "#{name}.yml")
        File.exists?(file) ? File.read(file) : nil
      end
    end

    # Serves inline presets declared in the fleet config's `presets:` block,
    # keyed by name. Values are the parsed YAML nodes, re-serialised on read so
    # `Preset.resolve` can reparse them like any other source.
    class MapLoader < Loader
      def initialize(@presets : Hash(String, YAML::Any))
      end

      def read?(name : String) : String?
        @presets[name]?.try(&.to_yaml)
      end
    end

    # Tries each source in order, returning the first that resolves `name`. The
    # order encodes precedence: inline presets > external dir > baked catalogue.
    class ChainLoader < Loader
      def initialize(@loaders : Array(Loader))
      end

      def read?(name : String) : String?
        @loaders.each do |loader|
          if content = loader.read?(name)
            return content
          end
        end
        nil
      end
    end

    def self.resolve(name : String, loader : Loader, seen : Array(String) = [] of String) : YAML::Any
      if seen.includes?(name)
        raise Error.new("preset inheritance cycle: #{(seen + [name]).join(" -> ")}")
      end

      raw = YAML.parse(loader.read(name)).as_h
      parent = raw[YAML::Any.new("inherit")]?.try(&.as_s)

      merged =
        if parent
          child = YAML::Any.new(raw.reject { |k, _| k.as_s == "inherit" })
          Ssherlock.deep_merge(resolve(parent, loader, seen + [name]), child)
        else
          YAML::Any.new(raw)
        end

      mh = merged.as_h
      options = mh[YAML::Any.new("options")]? || YAML::Any.new({} of YAML::Any => YAML::Any)
      checks = mh[YAML::Any.new("checks")]? || YAML::Any.new({} of YAML::Any => YAML::Any)
      YAML::Any.new({
        YAML::Any.new("options") => options,
        YAML::Any.new("checks")  => checks,
      })
    end

    # Resolves `name` and renders it as YAML for the `presets` subcommand.
    # Commands are stripped of the trailing newline their `|` block scalars
    # carry, so each renders as a clean single-line scalar instead of the
    # quoted blank-line form YAML would otherwise emit.
    def self.dump(name : String, loader : Loader) : String
      strip_commands(resolve(name, loader)).to_yaml
    end

    private def self.strip_commands(preset : YAML::Any) : YAML::Any
      root = preset.as_h.dup
      checks = root[YAML::Any.new("checks")]?.try(&.as_h)
      return YAML::Any.new(root) unless checks

      sections = {} of YAML::Any => YAML::Any
      checks.each do |section_name, section|
        cleaned = {} of YAML::Any => YAML::Any
        section.as_h.each do |check_name, spec|
          sh = spec.as_h.dup
          if command = sh[YAML::Any.new("command")]?
            sh[YAML::Any.new("command")] = YAML::Any.new(command.as_s.strip)
          end
          cleaned[check_name] = YAML::Any.new(sh)
        end
        sections[section_name] = YAML::Any.new(cleaned)
      end
      root[YAML::Any.new("checks")] = YAML::Any.new(sections)
      YAML::Any.new(root)
    end
  end
end
