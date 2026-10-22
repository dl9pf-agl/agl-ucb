# agl-ucb

Umbrella for the AGL kas build: kas fragments (`kas/`), pinned external layers (`kas/pins.yml`) and the entry
script `scripts/aglsetup.sh`. kas clones the AGL layers `meta-agl`, `meta-agl-demo` and `meta-agl-devel` into this
checkout on first use.

```
git clone https://github.com/dl9pf-agl/agl-ucb && cd agl-ucb
scripts/aglsetup.sh -m qemux86-64     # kas-container shell; then: bitbake agl-image-minimal
```

## Working on a layer (dev mode, opt-in)

Without `commit:` kas hard-resets a clean layer clone to the branch tip on every run, which drops unpushed
commits (a dirty clone is skipped). To edit a layer, clone once as above, then:

```
scripts/aglsetup.sh --dev -m qemux86-64
```

`--dev` adds `kas/local/dev.yml`: the three layers are plain local directories that kas never fetches, resets or
moves. Without `--dev`, `aglsetup.sh` warns when a layer has local changes. With plain `kas`/`kas-container`
append `kas/local/dev.yml` to the config chain.

## CI

CI appends one generated fragment with `commit:` (fork PRs: the fork `url:`) for the repo under test.
Definition: <https://github.com/dl9pf-agl/agl-ci>.
