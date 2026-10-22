---
name: yocto-bitbake
description: Yocto/bitbake knowledge for working in agl-ucb - layer vs git-repo boundaries (meta-agl contains several layers), what invalidates sstate signatures, yocto-check-layer requirements, recovering from an interrupted build, useful bitbake commands, and known fetcher gotchas. Consult when reading bitbake logs, debugging do_fetch/do_compile, explaining unexpected rebuilds, or touching layer.conf/LAYERDEPENDS. For kas/kas-container mechanics see the kas-operations skill.
---

# Yocto / bitbake in agl-ucb

Pairs with `kas-operations` (wrapper mechanics). This file is about bitbake/Yocto itself.

## 1. Layers
- A layer is a directory with `conf/layer.conf` (`BBFILE_COLLECTIONS`, `BBFILE_PATTERN_*`, `BBFILE_PRIORITY_*`, usually `LAYERDEPENDS_*`, `LAYERSERIES_COMPAT_*`). A directory without it is only a container.
- Git repo boundary != layer boundary: the `meta-agl` repo has no root `conf/layer.conf`; its layers are subdirs (`meta-agl-core`, `meta-agl-bsp`, `meta-pipewire`, ...). `kas/base.yml` lists the used ones under `layers:`; `meta-agl-demo` and `meta-agl-devel` use `layers: {}` and let `kas/feature/*.yml` add theirs.
- Some AGL sublayers declare no `LAYERDEPENDS` despite needing others (many `.bbappend` into other layers): upstream metadata gap, tools cannot discover it, add the layers by hand (e.g. `--additional-layers` for yocto-check-layer).

## 2. What invalidates sstate (broadly)
| Change | Effect |
|---|---|
| Moving the dir of the outermost kas config | `BBPATH` changes -> nearly all signatures: one full rebuild, not a bug. |
| Moving a layer or recipe | recipe `FILE` is a signature input: partial or full rebuild even with identical content. |
| Different `kas/feature/*.yml` set | changes `DISTRO_FEATURES`/`IMAGE_FEATURES`/layers; the further upstream, the more rebuilds. |
| Switching `kas/pins.yml` <-> `floating.yml`, or a bumped pin | new source revisions rebuild what depends on them. |
`Sstate summary: Wanted N ... Current 0 (0% match, 0% complete)` = full rebuild ahead.

## 3. yocto-check-layer
- Needs `--dependency <root>...` (scanned for `conf/layer.conf` to resolve `LAYERDEPENDS`) plus `--additional-layers` for layers lacking `LAYERDEPENDS`.
- Must run on a bare config (no AGL layers preloaded): it adds the layer under test itself, so an already-loaded layer gives a duplicate `BBFILE_COLLECTIONS` conflict. The agl-ci engine uses its own bare base for this.
- It runs a full world signature dump (`bitbake -S lockedsigs world`, then a `-k` pass): minutes, even warm. Silence is not a hang; check for live children.

## 4. Interrupted build
A SIGTERM mid-`make -j` leaves a static archive without ranlib index (`archive has no index; run ranlib to add one`, later `undefined reference to 'main'`) or a git mirror in `build/downloads/git2/<host>.<org>.<repo>.git` with invalid HEAD (`git fsck --full`; bitbake reports `Unable to find revision ... even from upstream`).
Recovery: `bitbake -c clean <recipe>`; for a mirror `rm -rf` it so `do_fetch` re-clones. Check network first (`curl -sI https://github.com`). Next time start the build detached (see kas-operations §6).

## 5. Commands
| Command | Use |
|---|---|
| `bitbake -e <target> \| grep -E '^VAR='` | final value of one variable, no build |
| `bitbake -p` | parse all recipes: fast syntax/parse check |
| `bitbake -S lockedsigs world` | dump signatures without building |
| `bitbake -c clean <recipe>` | clean one recipe |
| `bitbake -c populate_sdk <target>` | build the SDK |
| `bitbake-layers show-layers` | confirm the expected layers loaded; non-interactive: `kas-container shell KASFILE -c "bitbake-layers show-layers"` |

## 6. Gotchas
- git fetcher requires `SRCREV` reachable from `branch=`. After an upstream force-push a still-valid tag SRCREV fails; fix with a `.bbappend` adding `nobranch=1` to `SRC_URI` (seen: `grpc_1.80.0.bb` from meta-openembedded, fixed in `meta-agl/meta-agl-core/recipes-devtools/grpc/grpc_%.bbappend`).
- Classic `oe-init-build-env`/`TEMPLATECONF` is not used here; kas generates `conf/`.
- SPDX tasks (`do_create_spdx`, `do_create_package_spdx`, `do_create_image_spdx`, `do_create_image_sbom_spdx`) at the end of an image build are normal.
