#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Lint for this repo: the workflows (actionlint, zizmor), the shell scripts (shellcheck) and the kas configuration
# (scripts/check-kas.py). The same script runs in CI (.github/workflows/lint.yml) and locally.
# Needs actionlint, zizmor and shellcheck (the agl-ci runner image has them; locally: agl-ci scripts/install-lint-tools.sh)
# and python3 with PyYAML. GH_TOKEN is optional; with it zizmor also runs its online audits.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
fail=0
run() { echo "::group::$*"; "$@" || { echo "FAILED: $1"; fail=1; }; echo "::endgroup::"; }
run actionlint -color
# Explicit path: the CI job has a second checkout (agl-ci/) inside the workspace that must not be linted here.
if [ -n "${GH_TOKEN:-}" ]; then run zizmor --format=github .github/workflows; else run zizmor --offline --format=github .github/workflows; fi
run shellcheck -x scripts/*.sh
run python3 scripts/check-kas.py
exit "$fail"
