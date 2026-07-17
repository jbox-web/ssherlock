require "baked_file_system"

module Ssherlock
  # The Claude Code skill(s) shipped inside the binary, so the analysis half
  # travels with the collector — the same baking trick as config/presets and
  # licenses/. The binary carries and installs the skill; it never runs it, an
  # LLM does. Source of truth is the repo `skills/` folder, baked at compile time.
  class BakedSkills
    extend BakedFileSystem

    bake_folder "../../skills"

    # Writes every baked skill file under `dir`, preserving its baked relative
    # path (e.g. dir/ssherlock-audit/SKILL.md), and returns the written paths.
    # Validates the whole set first, so an existing destination aborts the
    # install before any file is written — unless `force`, which overwrites.
    def self.install(dir : String, force : Bool = false) : Array(String)
      dests = files.map { |file| {file.path, File.join(dir, file.path)} }
      unless force
        dests.each do |(_, dest)|
          raise Error.new("#{dest} already exists; pass --force to overwrite") if File.exists?(dest)
        end
      end
      dests.map do |(path, dest)|
        FileUtils.mkdir_p(File.dirname(dest))
        File.write(dest, get(path).gets_to_end)
        dest
      end
    end

    # Writes every baked skill file's raw content to `io`, back to back. Reads
    # through `get` so the baked reader is fresh, not a consumed `files` handle.
    def self.print(io : IO) : Nil
      files.each { |file| io.puts(get(file.path).gets_to_end) }
    end
  end
end
