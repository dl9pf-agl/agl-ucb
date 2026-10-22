#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Clone meta-agl, meta-agl-demo, meta-agl-devel into this checkout, where kas/base.yml expects them
# (path-only). Same script on a developer desk and in every CI (GitHub, GitLab, Forgejo).
#
#   scripts/checkout-layers.sh                 default-branch tip of each layer
#   LAYER_meta_agl=https://github.com/me/meta-agl@<sha> scripts/checkout-layers.sh
#                                              one layer from another URL at a commit/ref (CI: repo under test)
#
# Env: AGL_LAYERS_BASE  base URL of the layer repos (default https://github.com/dl9pf-agl)
#      AGL_FULL=1       fetch full history instead of depth 1
#      FORCE=1          also move an existing clone that has local changes (default: refuse)
# An existing clone is left alone unless a LAYER_<name> override is given for it.
set -euo pipefail
root="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
base="${AGL_LAYERS_BASE:-https://github.com/dl9pf-agl}"
depth=(--depth 1); [ -z "${AGL_FULL:-}" ] || depth=()

for repo in meta-agl meta-agl-demo meta-agl-devel; do
  var="LAYER_${repo//-/_}"; spec="${!var:-}"; dir="$root/$repo"
  url="$base/$repo.git"; ref=HEAD
  if [ -n "$spec" ]; then url="${spec%@*}"; ref="${spec##*@}"; [ "$ref" != "$spec" ] || ref=HEAD; fi

  if [ -d "$dir/.git" ]; then
    if [ -z "$spec" ]; then echo "$repo: kept ($(git -C "$dir" rev-parse --short HEAD))"; continue; fi
    if [ -n "$(git -C "$dir" status --porcelain)" ] && [ -z "${FORCE:-}" ]; then
      echo "$repo: local changes, refusing to move it (FORCE=1 to override)" >&2; exit 1; fi
  else
    git init -q "$dir"
  fi
  git -C "$dir" remote get-url origin >/dev/null 2>&1 && git -C "$dir" remote set-url origin "$url" || git -C "$dir" remote add origin "$url"
  git -C "$dir" fetch -q "${depth[@]}" origin "$ref"
  git -C "$dir" checkout -q --detach FETCH_HEAD
  echo "$repo: $(git -C "$dir" rev-parse --short HEAD) from $url ($ref)"
done
