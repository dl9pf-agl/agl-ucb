#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Write the pins file of a release from a `kas dump --resolve-refs` of all fragments.

Called by scripts/prepare-release.sh (which makes the dump). Offline and testable: it only reads YAML.
What it does:
  - takes every repo of the dump with its resolved commit (each must be a 40-hex SHA);
  - refuses when a repo is defined with a different url or branch in different fragments of kas/
    (kas would silently take one of them);
  - refuses when the dump does not honour an entry of kas/pins.yml (the resolved commit differs from the pin);
  - lists repos that kas/pins.yml does not pin (expected: the three AGL layers; anything else was resolved
    to the branch tip of now and is flagged);
  - writes kas/releases/pins_<branch>_<version>.yml in the format of kas/pins.yml.
"""
import argparse
import datetime
import re
import sys
from pathlib import Path

import yaml

# A full git commit id. A value that YAML reads as a number (all digits) or that is shorter is NOT accepted: better to refuse
# than to pin a truncated or mangled id.
SHA = re.compile(r"[0-9a-f]{40}")
# The repos that are expected NOT to be in kas/pins.yml (they float on their branch there). Any other repo that is missing
# from kas/pins.yml gets a warning below.
AGL_LAYERS = {"meta-agl", "meta-agl-demo", "meta-agl-devel"}


def load(path):
    # Read a YAML file that must be a mapping (every kas file is); stop with a clear message otherwise.
    d = yaml.safe_load(Path(path).read_text())
    if not isinstance(d, dict):
        sys.exit(f"{path}: top level is not a mapping")
    return d


def fragment_conflicts(kas_dir):
    """repo -> {(url, branch): [files]} for repos declared with different url/branch in different fragments."""
    # When two fragments declare the same repo with a different url or branch, kas merges them and the later file silently
    # wins. For a release that would pin a repo from a place nobody intended, so we look for it ourselves.
    seen = {}
    for f in sorted(Path(kas_dir).rglob("*.yml")):
        # Not fragments that declare repos: pins.yml only pins, floating.yml is the unpinned alternative, files under
        # kas/releases are our own output (and older release files), *.lock.yml are kas lock files.
        if f.name in ("pins.yml", "floating.yml") or "releases" in f.parts or f.name.endswith(".lock.yml"):
            continue
        for name, r in (load(f).get("repos") or {}).items():
            r = r or {}
            # Only entries that say where the repo comes from count; an entry without url and branch just adds layers.
            if r.get("url") or r.get("branch"):
                # seen[repo][(url, branch)] = the files that declare exactly this
                seen.setdefault(name, {}).setdefault((r.get("url"), r.get("branch")), []).append(f.name)
    # A conflict = one repo with more than one distinct (url, branch).
    return {n: v for n, v in seen.items() if len(v) > 1}


def main():
    # The command line is filled in by prepare-release.sh; --ucb-commit and --kas-version only go into the file header.
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dump", required=True, help="output of kas dump --resolve-refs")
    ap.add_argument("--kas-dir", required=True, help="the kas/ directory of agl-ucb")
    ap.add_argument("--out", required=True)
    ap.add_argument("--branch", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--ucb-commit", default="unknown")
    ap.add_argument("--kas-version", default="unknown")
    a = ap.parse_args()

    # Step 1: read the repos out of the dump. The dump looks like  repos: {name: {url:, branch:, commit: <40 hex>, layers:}}.
    # `repos` becomes {name: commit}.
    repos = {n: (r or {}).get("commit") for n, r in (load(a.dump).get("repos") or {}).items()}
    if not repos:
        sys.exit("the dump contains no repos")
    # Every repo needs a resolved 40-hex commit. A missing one means the dump was made without --resolve-refs (branch names
    # instead of commits); a non-string means YAML read an all-digit id as a number.
    bad = sorted(n for n, c in repos.items() if not (isinstance(c, str) and SHA.fullmatch(c)))
    if bad:
        sys.exit(f"no resolved 40-hex commit for: {', '.join(bad)} (was the dump made with --resolve-refs?)")

    # Step 2: refuse repos that two fragments declare differently (see fragment_conflicts). Only agl-ucb's own fragments are
    # compared; repos declared inside the layers' own kas files are not (a known limit).
    conflicts = fragment_conflicts(a.kas_dir)
    if conflicts:
        for n, v in sorted(conflicts.items()):
            print(f"ERROR: {n} is declared differently: " + "; ".join(f"{u} {b} in {','.join(f)}" for (u, b), f in v.items()), file=sys.stderr)
        sys.exit(1)

    # Step 3: kas/pins.yml is the existing set of pins (overrides: repos: {name: {commit}}). The dump was made WITH pins.yml as
    # the last fragment, so every repo it pins must have come out at exactly its pinned commit. If not, kas did not apply the
    # pin, and writing the file would pin something other than the validated set.
    pins = (load(Path(a.kas_dir) / "pins.yml").get("overrides") or {}).get("repos") or {}
    ignored = sorted(n for n in pins if n in repos and repos[n] != (pins[n] or {}).get("commit"))
    if ignored:
        sys.exit(f"kas did not honour kas/pins.yml for: {', '.join(ignored)}")

    # Step 4: repos in the dump that pins.yml does not pin were resolved to their branch tip of now. For the three AGL layers
    # that is the point of this script. Any other repo is reported (below) because it means pins.yml misses a pin.
    extra = sorted(set(repos) - set(pins))

    # Step 5: write the release file in the format of kas/pins.yml: header version 22 and overrides: repos: {name: {commit}},
    # sorted by name so that two runs on the same state give identical files. The comment lines say where it came from.
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    lines = [
        "# SPDX-License-Identifier: MIT",
        f"# Release pins {a.branch} {a.version}. Written by scripts/prepare-release.sh on {stamp}. Do not edit; never reuse a version.",
        f"# From agl-ucb {a.ucb_commit} and kas {a.kas_version}: every repo that any fragment of kas/ defines, resolved to the commit below.",
        f"# agl-ci release.yml builds tag {a.branch}_{a.version} with this file INSTEAD of kas/pins.yml.",
        "header:",
        "  version: 22",
        "overrides:",
        "  repos:",
    ]
    for n in sorted(repos):
        lines += [f"    {n}:", f"      commit: {repos[n]}"]
    Path(a.out).write_text("\n".join(lines) + "\n")

    # Step 6: tell the engineer what was done. Counting: "from kas/pins.yml" are the repos that were already pinned there.
    print(f"{len(repos)} repos pinned in {a.out}")
    print(f"  from kas/pins.yml: {len(repos) - len(extra)}")
    print(f"  resolved now (not in kas/pins.yml): {', '.join(extra) or 'none'}")
    for n in extra:
        if n not in AGL_LAYERS:
            print(f"WARNING: {n} is not pinned in kas/pins.yml: it was resolved to its branch tip of now. Pin it there first, or accept that.")


if __name__ == "__main__":
    main()
