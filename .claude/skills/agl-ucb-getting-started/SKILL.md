---
name: agl-ucb-getting-started
description: How to build AGL locally from agl-ucb - scripts/aglsetup.sh, choosing machine and features, listing targets, first run, dev mode, what Docker/kas-container needs, proprietary R-Car boards. Consult BEFORE running a first build in this repo, answering "how do I build X for Y", or when aglsetup.sh complains about a machine, feature or local changes.
---

# Getting started (agl-ucb)

agl-ucb is the umbrella checkout: kas fragments in `kas/`, the entry script `scripts/aglsetup.sh`, nothing else. kas clones `meta-agl`, `meta-agl-demo`, `meta-agl-devel` into the checkout and the external layers into `external/` and `bsp/` on first use (git-ignored). For kas/container details see the `kas-operations` skill; this one is the user path.

## Flow
```
git clone https://github.com/dl9pf-agl/agl-ucb && cd agl-ucb
scripts/aglsetup.sh --list-targets                 # target -> feature(s) -> owning repo
scripts/aglsetup.sh -m qemux86-64 [feature ...]    # interactive kas-container shell
bitbake agl-image-minimal                          # inside the shell, you run it
```
- Machine = a file `kas/machine/<m>.yml`; feature = `kas/feature/<f>.yml`. Any combination of existing files works; there is no allow-list here (`ci/build-matrix.yaml` in the layer repos is the curated CI set, not a limit).
- List only the **top-level** feature of a target: a feature that already includes another (`agl-kvm` includes `agl-demo`) needs just itself. `--list-targets` is hand-kept text, not derived from recipes; trust a build over it.
- Needs Docker (or podman) for `kas-container`. A permission error although you are in group `docker` is a stale group in the shell, not a real denial. Without `KAS_CONTAINER_IMAGE` the upstream kas image is used; it lacks the lint tools the AGL builder has.
- `-b DIR` uses a separate build directory per combination; the default is the shared `build/`. `AGL_SSTATE_DIR` / `AGL_DL_DIR` share caches across builds (opt-in).
- Long builds: run detached with a log file, never as a foreground command that can be killed (a kill mid-compile corrupts artifacts). Details: `kas-operations` section 6.

## Working on a layer: `--dev`
Without `commit:` kas hard-resets a clean layer clone to its branch tip on every run, and unpushed commits are lost. To edit `meta-agl*`: run once without `--dev` (clones), then always `scripts/aglsetup.sh --dev ...` (kas never touches the three clones). aglsetup.sh warns when a clone has local changes and `--dev` is missing.

## Boards with proprietary parts
`h3ulcb`, `h3ulcb-kf`, `m3ulcb`, `m3ulcb-kf` (not the `-nogfx` variants): aglsetup.sh runs the R-Car multimedia package hook from meta-agl once meta-agl is cloned; on a first-ever run it is skipped with a warning, run again. EULA acceptance (`EULA_<MACHINE>=1`) is not a kas setting here; CI sets it from the matrix, locally set it yourself. The warning text points to `docs/setup.md`, which does not exist in this repo.

## Pinned or floating
Default chain ends with `kas/pins.yml` (external layers pinned). `AGL_FLOATING=1` swaps in `kas/floating.yml` (no pins). Details: `agl-ucb-pins-and-releases`.

## What this is not
CI is not run from here. agl-ci's `layer-ci.yml` (called by the layer repos) builds; agl-ucb only holds the fragments it reads. Do not add CI logic to this repo.
