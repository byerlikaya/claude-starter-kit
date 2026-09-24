class Crewforth < Formula
  desc "Your engineering crew for Claude Code — agents, skills and tool-level gates"
  homepage "https://github.com/Crewforth/crewforth"
  url "https://github.com/Crewforth/crewforth/releases/download/v1.0.0/crewforth-1.0.0.tgz"
  sha256 "5f0a3612f64784ac0abfee878d362b674fd6d975b0b346153f86ff080a47d48a"
  version "1.0.0"
  license "MIT"

  def install
    libexec.install "start.sh", "adopt.sh", "kit", "VERSION"
    (bin/"crewforth").write <<~SH
      #!/bin/bash
      # Stage the bundled payload in a temp dir so start.sh's self-cleanup is harmless.
      stage="$(mktemp -d)"
      cp -R "#{libexec}/." "$stage/"
      case "${1:-}" in
        adopt|update) script=adopt.sh; shift ;;
        init)         script=start.sh;  shift ;;
        *)            script=start.sh ;;
      esac
      bash "$stage/$script" "$@"; rc=$?
      rm -rf "$stage"
      exit $rc
    SH
  end

  test do
    assert_match "Usage", shell_output("#{bin}/crewforth --help 2>&1")
  end
end
