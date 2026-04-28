# Homebrew formula for pathmgr.
#
# To publish:
#   1. Tag a release (e.g. v0.2.0) and push to GitHub.
#   2. Update `homepage`, `url`, and `sha256` below to match the release.
#   3. Either:
#        a. Drop this file into a personal tap repo (e.g.
#           `homebrew-pathmgr/Formula/pathmgr.rb`), then
#           `brew install <user>/pathmgr/pathmgr`, or
#        b. Submit to homebrew-core as a new formula PR.
#
# To compute SHA256 for the release tarball:
#   curl -sL https://github.com/<user>/pathmgr/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
#
# To install locally for testing without a tap:
#   brew install --build-from-source ./Formula/pathmgr.rb

class Pathmgr < Formula
  desc "Tiny C utility that turns a directory list into a PATH value"
  homepage "https://github.com/grazij/pathmgr"
  url "https://github.com/grazij/pathmgr/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_TARBALL_SHA256"
  license "MIT"
  head "https://github.com/grazij/pathmgr.git", branch: "main"

  def install
    system "make", "build", "VERSION=#{version}"
    bin.install "pathmgr"
    pkgshare.install "examples"
  end

  test do
    cfg = testpath/"config"
    cfg.write <<~EOS
      #{testpath}
      /nonexistent/dir
    EOS

    # Bare colon-joined output, exit 3 because /nonexistent/dir is skipped.
    output = shell_output("#{bin}/pathmgr -c #{cfg} -q", 3)
    assert_equal testpath.to_s, output.strip

    # -V prints version.
    assert_match version.to_s, shell_output("#{bin}/pathmgr -V")
  end
end
