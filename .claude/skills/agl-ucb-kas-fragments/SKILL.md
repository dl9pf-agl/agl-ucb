---
name: agl-ucb-kas-fragments
description: Layout and rules of the kas fragments in agl-ucb (base, machine, feature, local, pins, floating) - how the chain is composed, how to add a machine or a feature, the env passthrough ":=" rule, what scripts/check-kas.py and scripts/lint.sh verify. Consult BEFORE editing anything under kas/ or scripts/check-kas.py.
---

# kas fragments (agl-ucb)

All files start with `# SPDX-License-Identifier: MIT` and `header: version: 22` (kas 5.5).

## Chain
`kas/base.yml : kas/machine/<m>.yml : kas/feature/<f>.yml... [: kas/local/*.yml] : kas/pins.yml` (pins last; kas applies `overrides:` after everything). CI adds generated fragments after these (agl-ci `ci-only.yml`, `layer-pin.yml`; never committed here).
- `base.yml`: `distro: agl`; clones the three AGL layers (`url` + `branch: master`, **no `commit:`**) and the core externals (bitbake 2.18, openembedded-core `wrynose`, ...) under `external/`.
- `machine/<m>.yml`: `machine:`, its BSP `repos:` (under `bsp/` or `external/`), and `local_conf_header` requiring `conf/include/agl_<m>.inc`. A board whose include file is missing in meta-agl fails late in a build.
- `feature/<f>.yml`: a **one-line static pointer** into the repo that owns the real fragment (`header.includes: [{repo: meta-agl-demo, file: kas/feature/agl-demo.yml}]`). Never put feature logic here; it lives in the owning layer repo, which also declares the layers the feature needs.
- `local/*.yml`: optional, selected by environment or flags, never in the default chain: `dev.yml` (layers become plain dirs), `sstate-shared.yml`, `dl-shared.yml`, `mirrors.yml`, `hashserv-rw.yml`, `hashserv-upstream.yml`.
- `pins.yml` / `floating.yml`: see `agl-ucb-pins-and-releases`.

## Add a machine
Copy the nearest `kas/machine/*.yml` (same SoC family), change `machine:`, BSP repos and the `require conf/include/agl_<m>.inc` line. Check that the include exists in meta-agl's tree. Add its BSP layer pin to `kas/pins.yml`. Then `scripts/check-kas.py` and a real `kas checkout` of the chain.

## Add a feature
1. Put the real fragment in the owning layer repo (`<repo>/kas/feature/<f>.yml`). 2. Add the pointer file here (copy `agl-xen.yml`, change repo and file). 3. If it needs an external layer, declare it in the owning fragment and pin it in `pins.yml`. 4. Add it to the CI matrix of the owning repo (`ci/build-matrix.yaml`) and to the target table in `scripts/aglsetup.sh` if users should find it.

## Env passthrough rule (do not "simplify")
A fragment that reads an OS variable (`AGL_SSTATE_DIR`, `AGL_DL_DIR`, `AGL_MIRROR_URL`, `AGL_HASHSERV_*`) lists it under `env:` **and** captures it with an immediate `:=` into `<NAME>_RESOLVED` before using it. A direct `${VAR}` inside a lazily expanded value arrived unexpanded in bitbake (reproduced with sanity.bbclass and yocto-check-layer). Removing the indirection brings the failure back; re-test with `bitbake -e` first.

## Checks
- `scripts/check-kas.py` (PyYAML only, no network, no kas): valid YAML mapping, integer `header.version`, includes of files of this repo exist, includes of other repos refer to a declared repo, `local_conf_header` values are strings, `pins.yml` commits are 40-hex. It does **not** resolve repos or run bitbake, and does not check that a pinned repo is declared somewhere (most are declared in the layer repos' feature fragments).
- `scripts/lint.sh` (also the `lint` workflow): actionlint, zizmor (workflows only), shellcheck on `scripts/*.sh`, `check-kas.py`. Run it before every PR.
- Moving the directory of the outermost kas config changes `BBPATH`: expect one full sstate miss.
