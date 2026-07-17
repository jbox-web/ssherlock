require "baked_file_system"

module Ssherlock
  # Third-party and project license texts embedded into the binary at compile
  # time, so the redistributed static binary always carries the notices required
  # by its statically-linked dependencies. The folder is assembled by the
  # `dev:licenses` / Makefile `licenses` task before compilation.
  class Licenses
    extend BakedFileSystem

    bake_folder "../../licenses"
  end
end
