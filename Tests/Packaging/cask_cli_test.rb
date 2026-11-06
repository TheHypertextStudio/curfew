# frozen_string_literal: true

# Optional argument: directory containing the verified, read-only mounted Curfew.app.
require "cask/cask_loader"
require "tmpdir"

Dir.mktmpdir("curfew-cask-cli-") do |directory|
  root = Pathname.new(directory)
  appdir = root / "Applications"
  binarydir = root / "bin"
  if ARGV.empty?
    %w[curfew-ctl curfew-mcp].each do |tool|
      executable = appdir / "Curfew.app/Contents/Resources" / tool
      executable.dirname.mkpath
      executable.write("#!/bin/sh\nexit 0\n")
      executable.chmod(0755)
    end
  else
    appdir.mkpath
    FileUtils.cp_r(Pathname.new(ARGV.fetch(0)) / "Curfew.app", appdir / "Curfew.app")
  end

  source = Pathname.new(__dir__).parent.parent / "Casks/curfew.rb"
  cask = Cask::CaskLoader::FromContentLoader.new(source.read).load(
    config: Cask::Config.new(explicit: {appdir: appdir.to_s})
  )
  binaries = cask.artifacts.select { |artifact| artifact.is_a?(Cask::Artifact::Binary) }
  raise "Both bundled commands must be installed" unless binaries.length == 2

  binaries.each do |binary|
    # Exercise Homebrew's actual linker without writing to the user's prefix.
    name = binary.source.basename
    binary.define_singleton_method(:target) { binarydir / name }
    binary.install_phase
    target = binary.target
    raise "Homebrew linked outside the disposable command directory" unless target.dirname == binarydir
    unless target.symlink? && target.realpath == binary.source.realpath
      raise "Homebrew did not link the bundled executable"
    end

    before = target.lstat.mtime
    binary.install_phase
    raise "Repeated installation changed the command" unless target.lstat.mtime == before

    binary.uninstall_phase
    raise "Homebrew left the command behind" if target.symlink?
    raise "Removing the link removed the bundled executable" unless binary.source.exist?
  end

  puts("Passed Homebrew CLI install, repeat install, and unlink checks.")
end
