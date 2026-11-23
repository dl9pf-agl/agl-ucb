#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Static check of the kas configuration in kas/ - no network, no kas, only PyYAML.

What it catches (each of these breaks a build only later, in a long kas run):
  - a file that is not valid YAML or not a mapping;
  - a missing or non-integer header.version;
  - an include of a file of this repo that does not exist;
  - an include of another repo ({repo: X, file: Y}) where X is not declared in any `repos:` of kas/;
  - local_conf_header entries that are not strings;
  - kas/pins.yml and kas/releases/pins_<branch>_<version>.yml (overrides.repos) entries without a 40-hex commit, or a release
    file with a wrong name.
It does not resolve repos or run bitbake; CI of the layer repos does that. It does not check that a pinned repo is declared
somewhere: most are declared in the feature fragments of the layer repos (meta-agl/kas/feature/*.yml), not in this repo.
Usage: scripts/check-kas.py [repo-root]     (default: the repo that contains this script)
"""
import re
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
errors = []


def err(path, msg):
    errors.append(f"{path.relative_to(root)}: {msg}")


docs = {}
for f in sorted((root / "kas").rglob("*.yml")):
    try:
        d = yaml.safe_load(f.read_text())
    except yaml.YAMLError as e:
        err(f, f"not valid YAML: {str(e).splitlines()[0]}")
        continue
    if not isinstance(d, dict):
        err(f, "top level is not a mapping")
        continue
    docs[f] = d

declared = {name for d in docs.values() for name in (d.get("repos") or {})}

for f, d in docs.items():
    h = d.get("header")
    if not isinstance(h, dict) or not isinstance(h.get("version"), int):
        err(f, "header.version is missing or not an integer")
        continue
    for inc in h.get("includes") or []:
        if isinstance(inc, str):
            if not (root / inc).is_file():
                err(f, f"includes {inc}, which does not exist")
        elif isinstance(inc, dict) and "repo" in inc and "file" in inc:
            if inc["repo"] not in declared:
                err(f, f"includes {inc['file']} of repo {inc['repo']}, which no kas/*.yml declares under repos:")
        else:
            err(f, f"unsupported include entry: {inc!r}")
    for key, val in (d.get("local_conf_header") or {}).items():
        if not isinstance(val, str):
            err(f, f"local_conf_header.{key} is not a string")


def check_pins(path):
    # A pins file (kas/pins.yml or a release file) is `overrides: repos: {name: {commit: <40 hex>}}`. It must pin at least one
    # repo, and every commit must be a plain 40-character hex string. A commit that YAML read as a number (all digits) is not a
    # string and is refused too: better to stop than to pin a mangled id.
    repos = (docs[path].get("overrides") or {}).get("repos") or {}
    if not repos:
        err(path, "overrides.repos is empty")
    for name, repo in repos.items():
        commit = (repo or {}).get("commit", "")
        if not (isinstance(commit, str) and re.fullmatch(r"[0-9a-f]{40}", commit)):
            err(path, f"overrides.repos.{name}.commit is not a 40-hex SHA: {commit!r}")


# The dev pins file, checked as before.
pins = root / "kas" / "pins.yml"
if pins in docs:
    check_pins(pins)
# One immutable pins file per release in kas/releases/ (made by scripts/prepare-release.sh): check its name (the tag name
# <branch>_<version> and the signature file names derive from it) and its content.
for rel in sorted((root / "kas" / "releases").glob("*.yml")):
    if not re.fullmatch(r"pins_[a-z]+_[0-9]+\.[0-9]+\.[0-9]+\.yml", rel.name):
        err(rel, "name must be pins_<branch>_<version>.yml (lower case branch, version x.y.z)")
    # `docs` only holds files that parsed as YAML mappings; a broken file was already reported in the loop at the top.
    if rel in docs:
        check_pins(rel)

if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"kas check: {len(docs)} files ok")
