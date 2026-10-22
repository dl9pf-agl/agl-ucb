---
name: kas-operations
description: Operational knowledge for kas and kas-container in agl-ucb - scripts/aglsetup.sh, how kas/ fragments are composed (base, machine, feature, pins, local), env vars (KAS_TARGET, KAS_BUILD_DIR, AGL_SSTATE_DIR, AGL_DL_DIR), the kas hard-reset trap on the meta-agl* clones and --dev mode, kas-container command grammar, and running long bitbake builds safely. Consult BEFORE running aglsetup.sh or any kas/kas-container command here, when a kas command fails confusingly (wrong target built, local layer changes lost, build broken after an interruption, sstate at 0%), and before moving/renaming anything under kas/ or editing a repos: entry.
---

# kas / kas-container in agl-ucb

Verified behaviour, not a tutorial. Quote the relevant part when explaining why.

## 1. Normal flow
```sh
git clone https://github.com/dl9pf-agl/agl-ucb && cd agl-ucb
scripts/aglsetup.sh -m qemux86-64 [feature ...]    # interactive kas-container shell; then: bitbake agl-image-minimal
scripts/aglsetup.sh --list-targets                  # target -> feature(s) table
```
`aglsetup.sh` builds the KASFILE chain `kas/base.yml : kas/machine/<m>.yml : kas/feature/<f>.yml... [: kas/local/dev.yml] [: kas/local/sstate-shared.yml] [: kas/local/dl-shared.yml] : kas/pins.yml` (`AGL_FLOATING=1` swaps pins.yml for floating.yml) and runs `KAS_TARGET=${KAS_TARGET:-agl-image-minimal} KAS_WORK_DIR=<repo> kas-container shell`. Same chain works with `kas-container build|checkout` directly.

## 2. Environment
| Need | How / gotcha |
|---|---|
| Docker | `kas-container` needs a daemon. Permission error although in group `docker`: wrap in `sg docker -c '...'` (stale group in the shell). Ask the user before sudo. |
| Container image | default `ghcr.io/siemens/kas/kas:<ver>`; it lacks `oelint-adv`. For the AGL builder set `KAS_CONTAINER_IMAGE=ghcr.io/dl9pf-agl/agl-ci/builder@<digest>` (digest in agl-ci `ci/builder.digest`). |
| `KAS_TARGET` | beats the YAML `target:` and the schema default (`core-image-minimal`). Wrong image built -> check this first. `bitbake <target>` inside the shell ignores it. |
| `KAS_BUILD_DIR` / `-b DIR` | separate build dir per machine/feature combo (default shared `build/`). |
| `AGL_SSTATE_DIR`, `AGL_DL_DIR` | opt-in shared caches; aglsetup.sh adds `kas/local/{sstate,dl}-shared.yml`, mounts the dir and forwards the variable. Sstate is split per `${DEFAULTTUNE}`; keep the `AGL_SSTATE_DIR_RESOLVED :=` indirection in sstate-shared.yml (lazy `=` of an OS-passthrough variable breaks sanity.bbclass). |
| `AGL_FLOATING` | non-empty: unpinned `kas/floating.yml`. |

kas-container forwards only: `TERM KAS_DISTRO KAS_MACHINE KAS_TARGET KAS_TASK KAS_CLONE_DEPTH KAS_PREMIRRORS DISTRO_APT_PREMIRRORS BB_NUMBER_THREADS PARALLEL_MAKE GIT_CREDENTIAL_USEHTTPPATH BB_HASHSERVE BB_HASHSERVE_UPSTREAM NO_COLOR TZ`, plus `KAS_BUILD_DIR DL_DIR KAS_REPO_REF_DIR SSTATE_DIR BB_HASHSERVE_DB_DIR KAS_BUILDTOOLS_DIR`. Anything else: `--runtime-args -e --runtime-args VAR=value` (two separate `--runtime-args`, one word each; see `RUNTIME_ARGS` in aglsetup.sh).

## 3. Fragments
- `kas/base.yml` clones meta-agl, meta-agl-demo, meta-agl-devel (`url:` + `branch: master`) and external layers into `external/` (bitbake, oe-core, meta-openembedded, meta-lts-mixins-rust). The five clone dirs are git-ignored.
- `kas/feature/<n>.yml` is a 1-line pointer into the repo owning the real fragment; features pull their own dependencies via `header.includes:`. Never expand dependencies by hand; pass top-level feature names.
- Machines: `kas/machine/<m>.yml`. `h3ulcb*`/`m3ulcb*` need the proprietary package hook (aglsetup.sh runs it once meta-agl is cloned).
- A `repos:` entry with `url:` null/empty is a local dir, never touched by kas. A kas config is resolved relative to the git root of the first file.
- Moving the directory of the outermost kas config changes `BBPATH` -> full sstate miss once. Expected, not a regression.

## 4. Hard-reset trap and dev mode
Facts (kas 5.5, tested): a CLEAN clone with `branch:` and no `commit:` is hard-reset to the branch tip on every kas run, so unpushed commits are lost; a DIRTY clone is skipped ("Repo ... is dirty - no checkout"); `commit:` pins exactly (a fork `url:` + SHA works; the warning "Using branch without commit ... is unsafe" is normal).
- To work on a layer: clone once with plain `aglsetup.sh`, then `aglsetup.sh --dev ...` (adds `kas/local/dev.yml`, which empties `url:`/`branch:` of the three layers). `--dev` requires the clones to exist.
- Without `--dev`, aglsetup.sh warns when a clone has local changes or unpushed commits.
- CI pins the repo under test with a generated fragment (`commit:`, fork `url:`), appended last; see the agl-ci `agl-ci-layer-engine` skill.

## 5. Command grammar
- `kas-container {checkout,build,shell} KASFILE[:KASFILE...]`; no positional target for `build`: use `KAS_TARGET` or `--target`.
- `kas-container shell KASFILE -c "cmd"` runs one non-interactive command (e.g. `bitbake-layers show-layers`, `bitbake -p`): the way to smoke-test from an agent session without a TTY.
- `kas menu <Kconfig>` is an interactive picker; aglsetup.sh is the scriptable sibling.

## 6. Long builds
Never run a long build as a foreground command that a harness can SIGTERM: a kill mid-`make -j` corrupts artifacts (`archive has no index; run ranlib`, git mirror with invalid HEAD -> misleading `Unable to find revision ... even from upstream`). Launch detached and tail the log:
```sh
setsid bash -c 'scripts/... > build.log 2>&1' < /dev/null > /dev/null 2>&1 & disown
```
After an interruption suspect corruption first: `bitbake -c clean <recipe>` via `kas-container shell ... -c`, or `rm -rf build/downloads/git2/<mirror>` (verify with `git fsck --full` and `curl -sI https://github.com`).
Cache signal: `Sstate summary: Wanted N Local 0 Mirrors 0 Missed N Current 0 (0% match...)` = full rebuild ahead (hours); high Current = incremental.
