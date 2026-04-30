# Homebrew formula for pathset.
#
# To publish:
#   1. Tag a release (e.g. v0.2.0) and push to GitHub.
#   2. Run `make formula VERSION=0.2.0` from the project root — it bumps
#      `url` and `sha256` here, mirrors the file to ../homebrew-tap, and
#      pushes both repos. Users then run:
#        brew tap grazij/tap
#        brew install grazij/tap/pathset
#   3. Or submit to homebrew-core as a new formula PR.
#
# To compute SHA256 for the release tarball:
#   curl -sL https://github.com/grazij/pathset/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
#
# To install locally for testing without a tap:
#   brew install --build-from-source ./Formula/pathset.rb

class Pathset < Formula
  desc "Tiny C utility that turns a directory list into a PATH value"
  homepage "https://github.com/grazij/pathset"
  url "https://github.com/grazij/pathset/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "c175090d6b9130921a5bacb79c6ae934966fa467f65619f98020cb56b955b753"
  license "MIT"
  head "https://github.com/grazij/pathset.git", branch: "main"

  def install
    system "make", "build", "VERSION=#{version}"
    bin.install "pathset"
    pkgshare.install "examples"
  end

  test do
    cfg = testpath/"config"
    cfg.write <<~EOS
      #{testpath}
      /nonexistent/dir
    EOS

    # Bare colon-joined output, exit 3 because /nonexistent/dir is skipped.
    output = shell_output("#{bin}/pathset -c #{cfg} -q", 3)
    assert_equal testpath.to_s, output.strip

    # -V prints version.
    assert_match version.to_s, shell_output("#{bin}/pathset -V")
  end
end
