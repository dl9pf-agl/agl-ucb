# agl-ucb

Umbrella for the AGL kas build: kas fragments (`kas/`), pinned external layers (`kas/pins.yml`) and the entry
script `scripts/aglsetup.sh`. The AGL layers `meta-agl`, `meta-agl-demo` and `meta-agl-devel` live in their own
repositories and are cloned into this checkout.

```
git clone https://github.com/dl9pf-agl/agl-ucb && cd agl-ucb
scripts/checkout-layers.sh            # clones the three layers (shallow) where kas/base.yml expects them
scripts/aglsetup.sh -m qemux86-64     # kas-container shell; then: bitbake agl-image-minimal
```

`scripts/checkout-layers.sh` is also what CI runs. To test a layer from another repository or commit:

```
LAYER_meta_agl=https://github.com/<you>/meta-agl.git@<commit> scripts/checkout-layers.sh
```

An existing clone is never moved unless you name it with `LAYER_<name>`, and never if it has local changes
(`FORCE=1` overrides). `AGL_FULL=1` fetches full history. CI definition: <https://github.com/dl9pf-agl/agl-ci>.
