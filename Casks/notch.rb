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
  # just `notch --hook` no matter where Homebrew lives.
  binary "#{appdir}/Notch.app/Contents/MacOS/Notch", target: "notch"

  caveats <<~EOS
    Notch is signed ad-hoc, not notarized, so Gatekeeper blocks it until you
    allow it once. This also blocks the `notch --hook` command, so do this
    before wiring up the Claude Code hooks:

      xattr -dr com.apple.quarantine "#{appdir}/Notch.app"

    or install with:  brew install --cask --no-quarantine notch

    Claude Code hooks: point them at the `notch` command this cask links,
    e.g. { "type": "command", "command": "notch --hook" }.
  EOS
end
