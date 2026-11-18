require "../spec_helper"

Spectator.describe Ssherlock::Licenses do
  # The list follows licenses.manifest, which follows the link line of the
  # static binary: an extra or a missing name means the two drifted apart.
  it "embeds exactly the notices of the manifest" do
    expect(Ssherlock::Licenses.files.map(&.path).sort!).to eq([
      "/admiral.txt",
      "/baked_file_system.txt",
      "/clib-Apache-2.0.txt",
      "/clib-Boehm-GC.txt",
      "/clib-GCC-runtime-exception.txt",
      "/crystal-env.txt",
      "/libssh2.txt",
      "/libyaml.txt",
      "/musl.txt",
      "/pcre2.txt",
      "/ssh2.txt",
      "/ssherlock.txt",
      "/zlib.txt",
    ])
  end

  it "records which libraries each grouped notice covers" do
    expect(Ssherlock::Licenses.get("/clib-Apache-2.0.txt").gets_to_end).to start_with("Used by: openssl, crystal\n")
  end

  # The GCC Runtime Library Exception 3.1 is an additional permission of the
  # GPLv3: libgcc is GPL-3.0-or-later WITH that exception, never GPL-2.0.
  it "names the license the GCC runtime exception applies to" do
    notice = Ssherlock::Licenses.get("/clib-GCC-runtime-exception.txt").gets_to_end
    expect(notice).to contain("libgcc is distributed under GPL-3.0-or-later WITH the following exception")
    expect(notice).not_to contain("GPL-2.0")
  end

  # MIT, BSD and zlib all require the copyright notice to be reproduced: the
  # notice of the library, not the blank of a license template.
  it "carries the copyright notice of each C library, as its authors wrote it" do
    expect(Ssherlock::Licenses.get("/libssh2.txt").gets_to_end).to contain("Copyright (C) 2009-2023 Daniel Stenberg")
    expect(Ssherlock::Licenses.get("/libyaml.txt").gets_to_end).to contain("Copyright (c) 2006-2016 Kirill Simonov")
    expect(Ssherlock::Licenses.get("/musl.txt").gets_to_end).to contain("Copyright © 2005-2020 Rich Felker, et al.")
    expect(Ssherlock::Licenses.get("/pcre2.txt").gets_to_end).to contain("University of Cambridge")
    expect(Ssherlock::Licenses.get("/zlib.txt").gets_to_end).to contain("Jean-loup Gailly and Mark Adler")
  end

  it "embeds no license template with its blanks left in" do
    # Through `get`, never the handles of `files`: those share one read
    # position, and a handle another example has read yields "", which would
    # match no template whatever the file holds.
    Ssherlock::Licenses.files.each do |file|
      content = Ssherlock::Licenses.get(file.path).gets_to_end
      expect(content).not_to be_empty
      expect(content).not_to match(/<year>|<owner>|<copyright holders>/)
    end
  end
end
