#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# aglsetup.sh-muscle-memory wrapper around `kas-container shell`, for local exploration only.
#
#   scripts/aglsetup.sh -m qemux86-64 agl-demo agl-devel
#
# Lives in agl-ucb - the one true top-level clone/entry point (base.yml/pins.yml/floating.yml/
# machine/*.yml all live here too), the same role https://github.com/YoeDistro/yoe-distro plays
# over its component layers. meta-agl/meta-agl-demo/meta-agl-devel nest inside this checkout
# (agl-ucb/meta-agl, ...) - same visual tree `repo init`+`repo sync` used to produce, just
# git-ignored clones kas fetches itself (base.yml declares all 3, see there) instead of a
# manifest. kas/feature/<name>.yml here is a 1-line static pointer into whichever of the 3 AGL
# repos actually owns that feature's real fragment - no runtime-generated file, nothing to
# detect or decide, kas's own repos-resolution already handles present-vs-fetch.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$REPO_ROOT"

usage() {
  cat <<EOF
Usage: $(basename "$0") [-m|--machine MACHINE] [-b|--builddir DIR] [feature [feature ...]]
       $(basename "$0") --list-targets

Drops you into an interactive kas-container shell for MACHINE plus the given features. Run
bitbake yourself once inside, e.g. \`bitbake agl-image-minimal\`.

  -m, --machine MACHINE   default: qemux86-64
  -b, --builddir DIR      use DIR as the kas build directory instead of the shared build/
  --list-targets          list known bitbake targets and the feature(s) each one needs, then exit
  -h, --help              this message

Environment variables:
  AGL_SSTATE_DIR   shared sstate cache dir across builds, bind-mounted in - unset: private
  AGL_DL_DIR       shared downloads dir across builds, bind-mounted in - unset: private
  AGL_FLOATING     non-empty: use kas/floating.yml (unpinned) instead of kas/pins.yml

Available machines:
$(for f in kas/machine/*.yml; do printf '  %s\n' "$(basename "$f" .yml)"; done)

Available features:
$(for f in kas/feature/*.yml; do printf '  %s\n' "$(basename "$f" .yml)"; done)
EOF
}

# Curated target -> feature-combo mapping, one kas/images.yaml per repo that actually defines
# that target's recipe (not derivable from recipes/layers alone - same reason
# ci/build-matrix.yaml is hand-curated too, just without that file's CI-tier/machine baggage).
# Format kept bash-parseable on purpose (no python/yaml dependency on the host): one line per
# target, `name: [feat, feat]` or `name: []`.
list_targets() {
  for repo in meta-agl meta-agl-demo meta-agl-devel; do
    local f="$repo/kas/images.yaml"
    [ -f "$f" ] || continue
    grep -E '^[A-Za-z0-9_-]+:\s*\[' "$f" | while IFS=: read -r target feats; do
      feats="$(echo "$feats" | tr -d '[]' | xargs)"
      printf '  %-45s %-20s (%s)\n' "$target" "${feats:-<none>}" "$repo"
    done
  done
}

MACHINE="qemux86-64"
BUILDDIR=""
FEATURES=()
while [ $# -gt 0 ]; do
  case "$1" in
    -m|--machine) MACHINE="$2"; shift 2 ;;
    -b|--builddir) BUILDDIR="$2"; shift 2 ;;
    --list-targets) echo "Known targets (target, feature(s), owning repo):"; list_targets; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; FEATURES+=("$@"); break ;;
    -*) echo "$(basename "$0"): unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) FEATURES+=("$1"); shift ;;
  esac
done

if [ ! -f "kas/machine/$MACHINE.yml" ]; then
  echo "$(basename "$0"): no kas/machine/$MACHINE.yml - see --help for the list" >&2
  exit 2
fi

KASFILES="kas/base.yml:kas/machine/$MACHINE.yml"
for f in "${FEATURES[@]}"; do
  [ -z "$f" ] && continue
  if [ ! -f "kas/feature/$f.yml" ]; then
    echo "$(basename "$0"): unknown feature \"$f\" - see --help for the list" >&2
    exit 2
  fi
  KASFILES="$KASFILES:kas/feature/$f.yml"
done
# Optional shared sstate/downloads cache across builds - opt-in, off unless set.
RUNTIME_ARGS="--runtime-args --security-opt --runtime-args label=disable"
if [ -n "${AGL_SSTATE_DIR:-}" ]; then
  mkdir -p "$AGL_SSTATE_DIR"
  KASFILES="$KASFILES:kas/local/sstate-shared.yml"
  RUNTIME_ARGS="$RUNTIME_ARGS --runtime-args -v --runtime-args $AGL_SSTATE_DIR:$AGL_SSTATE_DIR --runtime-args -e --runtime-args AGL_SSTATE_DIR=$AGL_SSTATE_DIR"
fi
if [ -n "${AGL_DL_DIR:-}" ]; then
  mkdir -p "$AGL_DL_DIR"
  KASFILES="$KASFILES:kas/local/dl-shared.yml"
  RUNTIME_ARGS="$RUNTIME_ARGS --runtime-args -v --runtime-args $AGL_DL_DIR:$AGL_DL_DIR --runtime-args -e --runtime-args AGL_DL_DIR=$AGL_DL_DIR"
fi
if [ -n "${AGL_FLOATING:-}" ]; then
  KASFILES="$KASFILES:kas/floating.yml"
else
  KASFILES="$KASFILES:kas/pins.yml"
fi

if [ -n "$BUILDDIR" ]; then
  export KAS_BUILD_DIR="$BUILDDIR"
fi

# h3ulcb/m3ulcb proprietary R-Car gfx/multimedia package copy (classic aglsetup.sh's
# 50_setup.sh equivalent - imperative, no kas mechanism for this). h3ulcb/h3ulcb-kf/m3ulcb/
# m3ulcb-kf only, not the -nogfx variants. Lives inside meta-agl, which may not be cloned yet
# on a first-ever run (kas hasn't started); skipped with a warning when that's the case.
case "$MACHINE" in
  h3ulcb|h3ulcb-kf|m3ulcb|m3ulcb-kf)
    hook="meta-agl/meta-agl-bsp/meta-rcar-gen3/scripts/setup_mm_packages.sh"
    if [ -f "$hook" ]; then
      echo "$(basename "$0"): running proprietary R-Car package hook for $MACHINE"
      ( export METADIR="$(cd meta-agl && pwd)"; source "$hook"; copy_mm_packages ) \
        || echo "$(basename "$0"): WARNING: proprietary package setup failed/incomplete" \
                 "for $MACHINE - see docs/setup.md for what's required" >&2
    else
      echo "$(basename "$0"): WARNING: $hook not found (meta-agl not cloned yet?)," \
           "skipping proprietary package setup for $MACHINE" >&2
    fi
    ;;
esac

echo "aglsetup.sh: kas shell $KASFILES"
echo "aglsetup.sh: common targets once inside: agl-image-boot, agl-image-minimal," \
     "agl-image-weston, agl-image-compositor"
# shellcheck disable=SC2086
KAS_TARGET="${KAS_TARGET:-agl-image-minimal}" KAS_WORK_DIR="$REPO_ROOT" \
  exec kas-container $RUNTIME_ARGS shell "$KASFILES"
