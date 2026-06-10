class Burnrate < Formula
  desc "Monitor AI coding agent credit burn rate from the macOS menu bar"
  homepage "https://github.com/kwaneung/burnrate"
  url "https://github.com/kwaneung/burnrate/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  head "https://github.com/kwaneung/burnrate.git", branch: "main"

  depends_on :macos
  depends_on xcode: ["14.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox", "--product", "burnrate"
    bin.install ".build/release/burnrate"
  end

  def caveats
    <<~EOS
      BurnRate is a menu bar app (no Dock icon).
      Run `burnrate`, then click the flame icon in the menu bar.
    EOS
  end

  test do
    assert_predicate bin/"burnrate", :exist?
  end
end
