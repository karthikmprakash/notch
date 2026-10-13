cask "notch" do
  version "0.1.0"
  sha256 "a6c01b4797077f5518d4acf2292306b2b39f0a1f5f7f2a3f847dec537f62034d"

  url "https://github.com/karthikmprakash/notch/releases/download/v#{version}/Notch-#{version}.zip"
  name "Notch"
  desc "Dynamic Island for the MacBook notch, with tiles and a Claude Code bridge"
  homepage "https://github.com/karthikmprakash/notch"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Notch.app"
  # Same binary the app uses for its Claude Code hooks, so the hook command is
  # just \`notch --hook\` no matter where Homebrew lives.
  binary "#{appdir}/Notch.app/Contents/MacOS/Notch", target: "notch"

  # Releases are signed ad-hoc until a Developer ID certificate is wired into
  # the release workflow. macOS treats a quarantined, non-notarized bundle
  # badly: the first time its executable runs, Gatekeeper kills the process and
  # deletes the bundle - which also breaks the \`notch --hook\` command that
  # Claude Code calls. Clearing the download's quarantine flag at install time
  # avoids that; drop this postflight once releases are notarized.
  # The step DSL has no appdir, so this targets the default location and
  # no-ops (thanks to the `|| true`) if you installed to a custom --appdir.
  postflight_steps do
    run "/bin/sh",
        args: ["-c", "xattr -dr com.apple.quarantine /Applications/Notch.app 2>/dev/null || true"]
  end

  caveats <<~EOS
    The quarantine flag is removed automatically because this build is signed
    ad-hoc rather than notarized. If macOS still refuses to open it, run:

      xattr -dr com.apple.quarantine "#{appdir}/Notch.app"

    and if you ever see it disappear from /Applications, that is Gatekeeper
    deleting a quarantined bundle: reinstall with

      brew reinstall --cask notch

    Claude Code hooks: point them at the \`notch\` command this cask links,
    e.g. { "type": "command", "command": "notch --hook" }.
  EOS
end
