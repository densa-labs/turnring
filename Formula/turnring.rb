class Turnring < Formula
  desc "Menu bar notifications when coding agents finish"
  homepage "https://github.com/densa-labs/turnring"
  url "https://github.com/densa-labs/turnring.git", tag: "v0.5.0"
  license "MIT"
  head "https://github.com/densa-labs/turnring.git", branch: "main"

  depends_on macos: :sonoma

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    contents = prefix/"Turnring.app/Contents"
    (contents/"MacOS").install ".build/release/turnring"
    contents.install "Resources/Info.plist"
    (contents/"Resources").install "Resources/AppIcon.icns", "Resources/icon/MenuBar.svg",
                                   "Resources/icon/MenuBarPaused.svg"
    system "codesign", "--force", "--sign", "-", prefix/"Turnring.app"
    bin.install_symlink contents/"MacOS/turnring"
  end

  def caveats
    "Allow notifications for Turnring when macOS asks after `brew services start turnring`."
  end

  service do
    run [opt_prefix/"Turnring.app/Contents/MacOS/turnring", "agent"]
    keep_alive crashed: true # restart on crash; the menu's Quit stays quit
    process_type :interactive
    log_path var/"log/turnring.log"
    error_log_path var/"log/turnring.log"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/turnring version")
  end
end
