#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Prepare the pins file of a release:  scripts/prepare-release.sh <branch> <version>
#   <branch>   the AGL release line, lower case letters only, e.g. vimba
#   <version>  e.g. 22.0.2
# It writes kas/releases/pins_<branch>_<version>.yml: EVERY repo that any fragment of kas/ defines (all machines, all
# features, kas/pins.yml), each resolved to one commit now. The three AGL layers float on their branch in kas/pins.yml;
# this file freezes them, and the externals, in one place. It is used by agl-ci release.yml INSTEAD of kas/pins.yml.
#
# It writes only that one new file into your working tree: kas runs in a fresh clone of the current HEAD under $TMPDIR (a kas run resets
# clean clones to the branch tip, which would drop unpushed work in meta-agl/ and the other nested clones). The clone is
# kept (about 1.5 GB) so that you can look at it; the path is printed. It does not commit or push.
# Needs: kas 5.x (pip install kas==5.5, the version of the builder image), git, python3 with PyYAML, network.
# Then: review the file, commit it, open a pull request, merge it, tag the merge commit (printed at the end).
#
# (The block above is also the --help text: usage() prints lines 3 to 14 of this file, so keep it at exactly those lines.)
#
# Flow of the script, in the order it runs:
#   1. check the two arguments            (wrong or missing: print the help, exit 2, nothing else happens)
#   2. preflight                          (file must not exist yet, kas must be installed, kas/ and scripts/ must be committed)
#   3. fresh clone of HEAD in $TMPDIR     (kas must not run in the working tree, see above)
#   4. build the list of ALL fragments    (base + every machine + every feature + pins.yml, in this order)
#   5. kas dump --resolve-refs            (clones every repo and prints one YAML with a 40-hex commit per repo)
#   6. prepare-release.py                 (checks the dump and writes the release file)
#   7. warn about floating recipes        (SRCREV = "${AUTOREV}"), warning only
#   8. print what to do next
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"   # the agl-ucb working tree that holds this script
usage() { sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; }

# 1. Arguments: exactly two; the branch is only lower case letters, the version is x.y.z. This is also what the tag
#    <branch>_<version> must look like later, so a bad name is stopped here, before kas runs for minutes.
[ "$#" -eq 2 ] && [[ "$1" =~ ^[a-z]+$ ]] && [[ "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { usage >&2; exit 2; }
branch="$1"; version="$2"
rel="kas/releases/pins_${branch}_${version}.yml"   # relative to the repository root; the file this script creates

# 2. Preflight.
#    A release file is immutable: an existing one is never overwritten (a changed file would break rebuilds of that release).
[ ! -e "$here/$rel" ] || { echo "$rel exists. A release file is never overwritten; a new release needs a new version." >&2; exit 1; }
command -v kas >/dev/null || { echo "kas not found (pip install kas==5.5)" >&2; exit 1; }
#    The work clone below is made from HEAD. Uncommitted changes in kas/ or scripts/ would be missing from it (and the
#    release would be made from files that nobody can see in git), so refuse.
if [ -n "$(git -C "$here" status --porcelain -- kas scripts)" ]; then
  echo "kas/ or scripts/ has uncommitted changes; the work clone is made from HEAD and would not see them. Commit or stash first." >&2; exit 1
fi
commit="$(git -C "$here" rev-parse HEAD)"   # recorded in the header of the release file: which agl-ucb it was made from

# 3. Fresh clone. kas clones the layers into the tree it runs in and, for a clean clone with a branch and no commit, hard-resets it
#    to the branch tip on every run. In your working tree that would throw away unpushed commits in meta-agl/ and the others.
#    --no-hardlinks: the clone must not share files with the working tree. The directory is NOT deleted (about 1.5 GB).
work="$(mktemp -d "${TMPDIR:-/tmp}/prepare-release.XXXXXX")"
echo "work clone: $work/ucb (kept; remove it when you are done) - agl-ucb at $commit"
git clone -q --no-hardlinks "$here" "$work/ucb"
cd "$work/ucb"

# 4. The chain of fragments: kas merges the colon-separated files in order, later files win. The order is base, all machines,
#    all features, pins.yml LAST so that its pinned commits apply to everything before it. Together this names every repo
#    that any image of any machine could use ("every known repo"). kas/local/* and kas/floating.yml are left out on purpose:
#    they add settings, not repos, and floating.yml would undo the pins.
chain="kas/base.yml"
for f in kas/machine/*.yml kas/feature/*.yml; do chain+=":$f"; done
chain+=":kas/pins.yml"

# 5. kas dump --resolve-refs clones every repo of the chain and prints the merged configuration with each branch replaced by
#    the commit it points to now. All repos are resolved in this one run, so each has exactly one commit. stdout is the YAML,
#    stderr (clone progress) goes to a log that is only shown when kas fails.
echo "resolving every repo of $(echo "$chain" | tr ':' '\n' | wc -l) fragments (clones them, takes a minute or two) ..."
KAS_WORK_DIR="$PWD" kas dump --resolve-refs "$chain" > "$work/dump.yml" 2> "$work/kas.log" || { tail -n 20 "$work/kas.log" >&2; exit 1; }

# 6. The converter checks the dump (every commit is 40-hex, kas honoured every pin of kas/pins.yml, no repo is declared two ways)
#    and writes the release file into the WORKING TREE (--out), not into the temporary clone. --kas-dir is the clone's kas/
#    because that is the HEAD state that the dump was made from.
python3 "$here/scripts/prepare-release.py" --dump "$work/dump.yml" --kas-dir "$work/ucb/kas" --out "$here/$rel" \
  --branch "$branch" --version "$version" --ucb-commit "$commit" --kas-version "$(kas --version | head -n 1 | cut -d" " -f2)"

# 7. Warning only (no failure, the owner decided to fix such recipes instead of gating on them): a pinned layer does not pin a recipe
#    whose SRCREV is ${AUTOREV}, because bitbake then asks the git remote for the newest commit at build time. The regex matches
#    a plain assignment at the start of a line, SRCREV or SRCREV_<name>, with = ?= ??= or :=, whose value is exactly "${AUTOREV}".
#    It does NOT match SRCREV:<override> (only active with that override) or an AUTOREV inside a conditional expression.
# shellcheck disable=SC2016
autorev="$(grep -rIlE '^SRCREV(_[A-Za-z0-9_-]+)?[[:space:]]*(\?\?=|\?=|:=|=)[[:space:]]*"\$\{AUTOREV\}"' meta-agl meta-agl-demo meta-agl-devel external \
  --include='*.bb' --include='*.bbappend' --include='*.inc' 2>/dev/null || true)"
if [ -n "$autorev" ]; then
  # shellcheck disable=SC2016
  echo 'WARNING: recipes with an unconditional SRCREV = "${AUTOREV}" (not reproducible):'
  while IFS= read -r f; do echo "  $f"; done <<< "$autorev"
fi

# 8. What the engineer does now. The tag goes on the MERGE commit of the pull request, not on a local commit, because the release
#    build checks out agl-ucb at the tag and must find the pins file there.
cat <<EOF

Next:
  1. read $rel (git diff) and commit it ("kas/releases: pins for ${branch} ${version}"), open a pull request, get it merged;
  2. tag the MERGE commit: git tag -s ${branch}_${version} <merge-commit> && git push origin ${branch}_${version}
     (the tag starts the release build; only release engineers may create it).
EOF
