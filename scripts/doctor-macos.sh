#!/usr/bin/env bash
set -u

failures=0
warnings=0

pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; warnings=$((warnings + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }

if [[ "$(uname -s)" == "Darwin" ]]; then
  pass "macOS detected ($(sw_vers -productVersion), $(uname -m))"
else
  fail "This setup requires macOS."
fi

if command -v git >/dev/null 2>&1; then
  pass "Git available ($(git --version))"
else
  fail "Git is missing. Install Xcode Command Line Tools."
fi

if [[ -d /Applications/Xcode.app ]]; then
  pass "Xcode.app found"
else
  fail "Xcode.app is not installed in /Applications."
fi

if xcode-select -p >/dev/null 2>&1; then
  developer_dir="$(xcode-select -p)"
  pass "Active developer directory: $developer_dir"
else
  fail "No active Xcode developer directory."
fi

if command -v xcodebuild >/dev/null 2>&1; then
  xcode_version="$(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
  pass "xcodebuild available ($xcode_version)"
else
  fail "xcodebuild is unavailable."
fi

if command -v swift >/dev/null 2>&1; then
  pass "Swift available ($(swift --version 2>/dev/null | head -n 1))"
else
  fail "Swift is unavailable."
fi

if command -v xcodegen >/dev/null 2>&1; then
  pass "XcodeGen available ($(xcodegen --version))"
else
  fail "XcodeGen is missing. Run: brew install xcodegen"
fi

if command -v xcbeautify >/dev/null 2>&1; then
  pass "xcbeautify available"
else
  warn "xcbeautify is optional but recommended for readable CI logs."
fi

if command -v gh >/dev/null 2>&1; then
  pass "GitHub CLI available ($(gh --version | head -n 1))"
  if gh auth status >/dev/null 2>&1; then
    pass "GitHub CLI authenticated"
  else
    warn "GitHub CLI is not authenticated. Run: gh auth login"
  fi
else
  warn "GitHub CLI is optional locally. Install with: brew install gh"
fi

if command -v xcrun >/dev/null 2>&1; then
  simulator_count="$(xcrun simctl list devices available 2>/dev/null | grep -c 'iPhone' || true)"
  if [[ "$simulator_count" -gt 0 ]]; then
    pass "Available iPhone Simulator devices: $simulator_count"
  else
    fail "No available iPhone Simulator runtime. Install one in Xcode Settings > Platforms."
  fi
else
  fail "xcrun is unavailable."
fi

printf '\nDoctor result: %d failure(s), %d warning(s).\n' "$failures" "$warnings"
exit "$failures"
