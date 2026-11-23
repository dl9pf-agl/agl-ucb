#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Offline test of scripts/prepare-release.py with small fixtures (no kas, no network). Run: scripts/prepare-release_test.sh
# The temporary directory it makes is left in place (path printed); remove it yourself.
#
# How it works: fixture() writes a tiny fake kas/ tree (three repos) plus a fake `kas dump` output next to it. The cases then
# damage one thing at a time and check that prepare-release.py accepts the good one and refuses or flags each damaged one.
# The real kas dump is NOT part of this test (it needs the network); it was run by hand and is what the wrapper does.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
tool="$here/scripts/prepare-release.py"
t="$(mktemp -d "${TMPDIR:-/tmp}/prepare-release-test.XXXXXX")"   # one directory per run, one subdirectory per case
echo "test directory: $t"
fails=0
ok() { echo "ok:   $*"; }
bad() { echo "FAIL: $*"; fails=$((fails + 1)); }
# sha N prints a fake 40-hex commit id that differs per N: "a" + 39 hex digits of N.
sha() { printf 'a%039x' "$1"; }   # starts with a letter: YAML reads an all-digit 40-char string as an integer (the tool refuses that, on purpose)

# fixture NAME: make $t/NAME/kas/{base.yml, machine/m.yml, feature/f.yml, pins.yml} and $t/NAME/dump.yml.
#   base.yml     declares meta-agl (a floating AGL layer) and bitbake (an external)
#   machine/m    declares meta-bsp (a BSP layer, external)
#   feature/f    declares meta-agl again, identically (allowed: same url and branch)
#   pins.yml     pins bitbake (sha 1) and meta-bsp (sha 2); meta-agl is NOT pinned, as in the real kas/pins.yml
#   dump.yml     what `kas dump --resolve-refs` would print: all three repos with a commit; meta-agl got sha 3 (its branch tip)
fixture() {
  local d="$t/$1"; mkdir -p "$d/kas/machine" "$d/kas/feature"
  cat > "$d/kas/base.yml" <<EOF
header: {version: 22}
repos:
  meta-agl: {url: https://example.org/meta-agl.git, branch: master}
  bitbake: {url: https://example.org/bitbake.git, branch: "2.18"}
EOF
  cat > "$d/kas/machine/m.yml" <<EOF
header: {version: 22}
repos:
  meta-bsp: {url: https://example.org/meta-bsp.git, branch: main}
EOF
  cat > "$d/kas/feature/f.yml" <<EOF
header: {version: 22}
repos:
  meta-agl: {url: https://example.org/meta-agl.git, branch: master}
EOF
  cat > "$d/kas/pins.yml" <<EOF
header: {version: 22}
overrides:
  repos:
    bitbake: {commit: $(sha 1)}
    meta-bsp: {commit: $(sha 2)}
EOF
  cat > "$d/dump.yml" <<EOF
header: {version: 22}
repos:
  meta-agl: {url: https://example.org/meta-agl.git, branch: master, commit: $(sha 3)}
  bitbake: {url: https://example.org/bitbake.git, commit: $(sha 1)}
  meta-bsp: {url: https://example.org/meta-bsp.git, commit: $(sha 2)}
EOF
}
# run DIR: call the converter on a fixture; prints its output (stdout and stderr), the caller reads the exit code from $?.
run() { python3 "$tool" --dump "$1/dump.yml" --kas-dir "$1/kas" --out "$1/out.yml" --branch testrel --version 0.0.1 --ucb-commit abc --kas-version "5.5" 2>&1; }

# 1. Good case: everything consistent. Must be accepted and the output file must have the right content and format.
fixture good
out="$(run "$t/good")"; rc=$?
if [ "$rc" -eq 0 ]; then ok "good dump is accepted"; else bad "good dump refused: $out"; fi
if [ "$(grep -c '^      commit: ' "$t/good/out.yml")" -eq 3 ]; then ok "3 repos written"; else bad "wrong number of repos in the output file"; fi
if grep -q "^    meta-agl:" "$t/good/out.yml" && grep -q "commit: $(sha 3)" "$t/good/out.yml"; then ok "the floating layer is pinned to its resolved commit"; else bad "layer commit missing"; fi
if grep -q '^  version: 22$' "$t/good/out.yml" && grep -q '^overrides:$' "$t/good/out.yml"; then ok "pins.yml format (header 22, overrides)"; else bad "wrong format"; fi
if echo "$out" | grep -q 'resolved now (not in kas/pins.yml): meta-agl'; then ok "the layer is listed as resolved now"; else bad "layer not listed"; fi
if echo "$out" | grep -q WARNING; then bad "unexpected warning for the AGL layer"; else ok "no warning for an AGL layer"; fi
if python3 -c "import yaml; d=yaml.safe_load(open('$t/good/out.yml')); assert sorted(d['overrides']['repos'])==['bitbake','meta-agl','meta-bsp']"; then ok "output is valid YAML with the expected repos"; else bad "output not parsable"; fi

# 2. A repo that kas/pins.yml does not pin and that is NOT an AGL layer (a new external somebody forgot to pin). The file is
#    still written (the dump has a commit for it) but the tool must warn that it was resolved to a branch tip.
fixture extra
cat >> "$t/extra/dump.yml" <<EOF
  meta-new: {url: https://example.org/meta-new.git, commit: $(sha 4)}
EOF
out="$(run "$t/extra")"
if echo "$out" | grep -q 'WARNING: meta-new is not pinned'; then ok "an unpinned non-layer repo is flagged"; else bad "unpinned repo not flagged"; fi

# 3. kas ignored a pin: the dump shows bitbake at sha 9 although pins.yml pins it at sha 1. Writing the file would not pin the
#    validated set, so the tool must refuse.
fixture ignored
sed -i "s/commit: $(sha 1)}/commit: $(sha 9)}/" "$t/ignored/dump.yml"
out="$(run "$t/ignored")"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q 'did not honour'; then ok "a pin that kas did not honour is refused"; else bad "ignored pin accepted"; fi

# 4. A commit that is not a 40-hex id (here a short one, as a dump made without --resolve-refs or a mangled file would give).
fixture short
sed -i "s/commit: $(sha 3)}/commit: abc123}/" "$t/short/dump.yml"
run "$t/short" >/dev/null; rc=$?
if [ "$rc" -ne 0 ]; then ok "a short commit is refused"; else bad "short commit accepted"; fi

# 5. Two fragments declare meta-agl with different urls: kas would silently take the later one. Must be refused.
fixture conflict
sed -i 's#https://example.org/meta-agl.git, branch: master#https://other.example.org/meta-agl.git, branch: master#' "$t/conflict/kas/feature/f.yml"
out="$(run "$t/conflict")"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q 'declared differently'; then ok "a conflicting declaration is refused"; else bad "conflict accepted"; fi

# 6. A dump without any repo (kas failed quietly, or the wrong file was given). Must be refused.
fixture empty
printf 'header: {version: 22}\nrepos: {}\n' > "$t/empty/dump.yml"
run "$t/empty" >/dev/null; rc=$?
if [ "$rc" -ne 0 ]; then ok "an empty dump is refused"; else bad "empty dump accepted"; fi

# 7. The wrapper checks its arguments first (exit code 2, before kas or git are touched), so these three run fast and offline.
"$here/scripts/prepare-release.sh" Vimba 1.2.3 >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok "upper case branch refused by the wrapper"; else bad "upper case branch accepted"; fi
"$here/scripts/prepare-release.sh" vimba 1.2 >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok "short version refused by the wrapper"; else bad "short version accepted"; fi
"$here/scripts/prepare-release.sh" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok "missing arguments refused by the wrapper"; else bad "missing arguments accepted"; fi

# Result: exit 0 only if every check above passed.
if [ "$fails" -eq 0 ]; then echo "all tests passed"; else echo "$fails test(s) failed"; exit 1; fi
