# frozen_string_literal: true

# Run with `brew ruby Tests/Packaging/cask_uninstall_test.rb`.
# The installed Homebrew dispatcher runs against a fake app and command sink.
require "cask/cask_loader"
require "tmpdir"

# Homebrew passes commands through this sink so the test never launches a real app.
class RecordingUninstallCommand < SystemCommand
  class UnregisterRefused < StandardError; end
  class << self
    attr_accessor :events, :refuse

    def run(executable, **options)
      unless executable.to_s.end_with?("/Curfew.app/Contents/MacOS/Curfew")
        raise "Unregister must use the bundled executable"
      end
      raise "Unregister must run before state cleanup" if options[:args] != ["--unregister-background-service"]
      raise "An unregister failure must abort removal" if options[:must_succeed] != true

      events << :unregister
      raise UnregisterRefused if refuse
    end
  end
end

Dir.mktmpdir("curfew-cask-uninstall-") do |directory|
  appdir = Pathname.new(directory)
  executable = appdir/"Curfew.app/Contents/MacOS/Curfew"
  executable.dirname.mkpath
  executable.write("#!/bin/sh\nexit 42\n")
  source = Pathname.new(__dir__).parent.parent/"Casks/curfew.rb"
  cask = Cask::CaskLoader::FromContentLoader.new(source.read).load(
    config: Cask::Config.new(explicit: { appdir: appdir.to_s }),
  )
  artifacts = cask.artifacts.sort
  uninstall = artifacts.find { |artifact| artifact.is_a?(Cask::Artifact::Uninstall) }
  raise "The cask must stop background recovery before removal" unless uninstall
  raise "Unregister must precede removing the app" if artifacts.index(uninstall) >= artifacts.index(
    artifacts.find { |artifact| artifact.is_a?(Cask::Artifact::App) },
  )
  if uninstall.directives[:quit] != "studio.hypertext.apps.curfew"
    raise "The cask must quit the production app after unregistering"
  end

  uninstall.define_singleton_method(:uninstall_quit) do |*_args, **_options|
    RecordingUninstallCommand.events << :quit
  end
  uninstall.define_singleton_method(:sleep) { |_seconds| 0 }

  RecordingUninstallCommand.events = []
  RecordingUninstallCommand.refuse = false
  uninstall.uninstall_phase(command: RecordingUninstallCommand)
  raise "Homebrew must unregister before quitting" if RecordingUninstallCommand.events != [:unregister, :quit]

  RecordingUninstallCommand.events = []
  uninstall.uninstall_phase(command: RecordingUninstallCommand, upgrade: true)
  raise "An upgrade must unregister before quitting" if RecordingUninstallCommand.events != [:unregister, :quit]

  RecordingUninstallCommand.events = []
  RecordingUninstallCommand.refuse = true
  begin
    uninstall.uninstall_phase(command: RecordingUninstallCommand)
    raise "Homebrew continued despite unregister refusal"
  rescue RecordingUninstallCommand::UnregisterRefused
    raise "Homebrew quit after unregister refusal" if RecordingUninstallCommand.events != [:unregister]
  end
  puts "Passed Homebrew uninstall ordering and refusal tests."
end
