cask "human-ram" do
  version "0.2.2"
  # Human RAM is ad-hoc signed (no paid Apple Developer certificate), and each
  # release is built fresh, so a pinned checksum would break installs whenever
  # someone rebuilds. Content is delivered over HTTPS from the project's own
  # GitHub releases. To pin instead, replace this with the sha256 from
  # "Scripts/release.sh".
  sha256 :no_check

  url "https://github.com/DerekHam/Human-RAM/releases/download/v#{version}/Human-RAM-v#{version}-macOS.dmg"
  name "Human RAM"
  desc "Menu-bar app that treats your attention like computer memory"
  homepage "https://github.com/DerekHam/Human-RAM"

  app "Human RAM (Shareable).app"

  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-dr", "com.apple.quarantine", "{{appdir}}/Human RAM (Shareable).app"]
  end

  caveats <<~EOS
    Human RAM is not notarized by Apple. Homebrew clears the download
    quarantine flag for you, so it opens without the "unidentified developer"
    warning. If you ever move the app by hand, run:
      xattr -dr com.apple.quarantine "/Applications/Human RAM (Shareable).app"
  EOS
end
