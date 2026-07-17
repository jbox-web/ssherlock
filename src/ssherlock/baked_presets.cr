require "baked_file_system"

module Ssherlock
  # The preset catalogues shipped inside the binary.
  class BakedPresets
    extend BakedFileSystem
    bake_folder "../../config/presets"

    # A Preset::Loader that reads baked "<name>.yml" content.
    class BakedLoader < Preset::Loader
      def read?(name : String) : String?
        BakedPresets.get("#{name}.yml").gets_to_end
      rescue BakedFileSystem::NoSuchFileError
        nil
      end
    end

    def self.loader : Preset::Loader
      BakedLoader.new
    end

    # Sorted names of the baked preset catalogues (filenames without ".yml"),
    # used by the `presets` subcommand to list what the binary ships.
    def self.names : Array(String)
      files.map { |f| File.basename(f.path, ".yml") }.sort!
    end
  end
end
