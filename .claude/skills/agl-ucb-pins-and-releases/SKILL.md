---
name: agl-ucb-pins-and-releases
description: Which repos kas/pins.yml pins in agl-ucb and which float, how overrides and floating.yml work, how to bump external pins, and how to get a reproducible release pin of all repos. Consult BEFORE editing kas/pins.yml or kas/floating.yml, bumping a layer, or reproducing a build exactly.
---

# Pins and releases (agl-ucb)

## Rules
- `kas/pins.yml` pins **external** layers only, in one place: `overrides: repos: <name>: commit: <40-hex>` (bitbake, openembedded-core, meta-openembedded, meta-qt6, meta-flutter, meta-virtualization, BSPs, ...). `kas/base.yml` and the machine/feature fragments declare where they come from; the pin file fixes the commit.
- **`meta-agl`, `meta-agl-demo` and `meta-agl-devel` are not pinned: they float on the tip of their branch** (decision 2026-10-28). Do not add them to `pins.yml`: kas applies `overrides:` last, so such a pin would beat the generated pin of a repo under test and a PR would silently build the pinned master (this produced green runs that built nothing).
- Bump the externals **together**. They are a validated-together set (aligned with the classic AGL manifest); one layer ahead of its partner breaks (meta-flutter ahead of oe-core hit `license-format` QA errors). Review the diff before committing; `scripts/check-kas.py` checks that every pin is 40-hex.
- `kas/floating.yml` is the unpinned alternative for local use (`AGL_FLOATING=1`): every repo resolves to the tip of its declared branch. Never used in CI.
- The comments in `pins.yml` and `floating.yml` mention `make lock`, `make pin-update` and `docs/setup.md`. **None of them exists in this repo** (no Makefile, no `docs/`). Bump by hand, or write the resolved commits with agl-ci's `ci/scripts/resolved-pins.sh` and review.

## Reproducing or releasing
A run on floating layers is not described by `pins.yml` alone. For a reproducible build or a release, use the **written-out pin**: agl-ci's `ci/scripts/resolved-pins.sh` prints the commit of every repo of a checked-out tree as a fragment in this file's format (the `matrix` job of every CI run shows it in its summary). Build with that file in place of `kas/pins.yml`: `kas/base.yml:...:resolved-pins.yml`. Tested: it brought a tree moved to older commits back to exactly the recorded ones, offline. Release pins must be commits on the declared branch (`master`), otherwise kas fetches. Store the file with the release.

## Pin bump checklist
1. Edit `pins.yml` (all affected entries). 2. `scripts/check-kas.py`. 3. `kas checkout` of one machine+feature chain, offline afterwards if you can. 4. A real build of `agl-image-minimal` on qemux86-64. 5. PR; the layer repos' CI picks agl-ucb's default branch at run time, so a merge changes what their next runs build.
