#!/bin/bash
# Writes the Homebrew cask for a release, and (optionally) pushes it to the tap.
#
#   tools/update-cask.sh <version> <sha256> [--tap-dir DIR] [--write] [--push]
#
#   <version>   version without the leading v, e.g. 0.1.0
#   <sha256>    sha256 of Notch-<version>.zip from the GitHub release
#   --write     also write Casks/notch.rb in this repo (for reference)
#   --tap-dir   clone of the tap repo to update (default: ../homebrew-tap)
#   --push      commit and push inside --tap-dir
#
# CI calls this with TAP_TOKEN set; locally you can run it by hand after a release.
set -euo pipefail

REPO="karthikmprakash/notch"
TAP_REPO="karthikmprakash/homebrew-tap"
VERSION=""
SHA=""
TAP_DIR="../homebrew-tap"
WRITE="no"
PUSH="no"

while [ $# -gt 0 ]; do
  case "$1" in
    --write)   WRITE="yes"; shift ;;
    --push)    PUSH="yes"; shift ;;
    --tap-dir) TAP_DIR="$2"; shift 2 ;;
    -*)        echo "unknown option: $1" >&2; exit 2 ;;
    *)         if [ -z "$VERSION" ]; then VERSION="$1"; elif [ -z "$SHA" ]; then SHA="$1"; else echo "unexpected argument: $1" >&2; exit 2; fi; shift ;;
  esac
done

[ -n "$VERSION" ] && [ -n "$SHA" ] || { echo "usage: $0 <version> <sha256> [--write] [--tap-dir DIR] [--push]" >&2; exit 2; }
echo "$SHA" | grep -Eq '^[0-9a-f]{64}$' || { echo "that does not look like a sha256: $SHA" >&2; exit 2; }

cask_body() {
  # Quoted heredoc: nothing here is shell-expanded. The placeholders are
  # substituted below, so backticks and $ in cask text stay literal.
  cat <<'RUBY' | sed -e "s/@VERSION@/$VERSION/g" -e "s/@SHA@/$SHA/g" -e "s|@REPO@|$REPO|g"
cask "notch" do
  version "@VERSION@"
  sha256 "@SHA@"

  url "https://github.com/@REPO@/releases/download/v#{version}/Notch-#{version}.zip"
  name "Notch"
  desc "Dynamic Island for the MacBook notch, with tiles and a Claude Code bridge"
  homepage "https://github.com/@REPO@"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Notch.app"
  # Same binary the app uses for its Claude Code hooks, so the hook command is
  # just `notch --hook` no matter where Homebrew lives.
  binary "#{appdir}/Notch.app/Contents/MacOS/Notch", target: "notch"

  # Releases are signed ad-hoc until a Developer ID certificate is wired into
  # the release workflow. macOS treats a quarantined, non-notarized bundle
  # badly: the first time its executable runs, Gatekeeper kills the process and
  # deletes the bundle - which also breaks the `notch --hook` command that
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

    Claude Code hooks: point them at the `notch` command this cask links,
    e.g. { "type": "command", "command": "notch --hook" }.
  EOS
end
RUBY
}

if [ "$WRITE" = "yes" ]; then
  mkdir -p Casks
  cask_body > Casks/notch.rb
  echo "wrote Casks/notch.rb (version $VERSION)"
fi

if [ ! -d "$TAP_DIR" ]; then
  echo "tap directory $TAP_DIR not found:"
  echo "  git clone https://github.com/$TAP_REPO.git \"$TAP_DIR\""
  echo "(local copy written to Casks/notch.rb if you passed --write)"
  exit 0
fi

mkdir -p "$TAP_DIR/Casks"
cask_body > "$TAP_DIR/Casks/notch.rb"
echo "updated $TAP_DIR/Casks/notch.rb (version $VERSION)"

if [ "$PUSH" = "yes" ]; then
  cd "$TAP_DIR"
  git add Casks/notch.rb
  if git diff --cached --quiet; then
    echo "tap already at $VERSION, nothing to push"
  else
    git -c user.name="${GIT_AUTHOR_NAME:-notch-bot}" \
        -c user.email="${GIT_AUTHOR_EMAIL:-notch-bot@users.noreply.github.com}" \
        commit -m "notch $VERSION"
    git push
    echo "pushed notch $VERSION to the tap"
  fi
fi
