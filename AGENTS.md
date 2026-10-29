# AGENTS.md

This is `agl-ucb`, the umbrella checkout for AGL builds: the kas fragments under `kas/` (base, machine, feature, local, pins) and the entry script `scripts/aglsetup.sh`. kas clones `meta-agl`, `meta-agl-demo` and `meta-agl-devel` into it. CI logic is not here; it lives in `dl9pf-agl/agl-ci`. Skills for working here are in `.claude/skills/`: `agl-ucb-getting-started`, `agl-ucb-kas-fragments`, `agl-ucb-pins-and-releases`, `agl-ucb-using-mirrors`, `kas-operations`, `yocto-bitbake`.

## Commands
- `scripts/lint.sh`: actionlint, zizmor, shellcheck of `scripts/*.sh`, `scripts/check-kas.py`. Run it before every pull request.
- `scripts/aglsetup.sh -m <machine> <features>`: interactive kas-container shell for local work (`--list-targets`, `--dev`).

## Rules for the fragments
- `kas/pins.yml` pins the external layers only; `meta-agl`, `meta-agl-demo` and `meta-agl-devel` float on their branch and must not be added (kas applies `overrides:` last and a pin would beat the generated pin of a repo under test).
- A feature fragment here is a one-line pointer to the repo that owns the real one.

## Working rules
- Show the complete commit message and the complete diff before any push or pull request; do not summarise them.
- Before every push: fetch, check that the pull request is still open and whether the branch needs a rebase onto its base; push only then.
- Name pull requests with their repository (`meta-agl#8`, not `#8`): the numbers repeat across repos.
- Rebase-merge only (the ruleset allows nothing else). Only commit or push when asked.
- A push to a pull request cancels its CI run in progress; do not push to a pull request with a cold build running without saying so.
- No links to chat sessions in commit messages or pull request texts; no tokens and no host addresses in committed files.
- Changes under `.github/`, `.claude/` and `ci/` are reviewed by the owner (`.github/CODEOWNERS`).

## AI assistants
AGL tracks AI involvement in contributions. The AGL documentation on AI coding assistants is linked from `ai-coding.md` in meta-agl; follow it for the commit trailer. This file does not restate the policy.
