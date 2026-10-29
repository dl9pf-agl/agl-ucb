---
name: agl-ucb-using-mirrors
description: How to use shared caches, a source/sstate mirror and a hash equivalence server with agl-ucb builds - kas/local/{sstate-shared,dl-shared,mirrors,hashserv-rw,hashserv-upstream}.yml, the AGL_* variables, trusted versus untrusted use, private mirrors for OEM members. Consult BEFORE setting AGL_MIRROR_URL, AGL_SSTATE_DIR, AGL_DL_DIR or AGL_HASHSERV_*, or when a build needs the network it should not.
---

# Caches and mirrors (agl-ucb)

All are optional local fragments; none is in the default chain. agl-ci's `ci/scripts/_kas_runtime_args.sh` appends each when its variable is set. `scripts/aglsetup.sh` handles only `AGL_SSTATE_DIR` and `AGL_DL_DIR` (adds the fragment, mounts the directory, forwards the variable) and `AGL_FLOATING`. **It does not add `mirrors.yml` or the hashserv fragments**: for those, append the fragment to your KASFILE chain yourself and forward the variable into the container as aglsetup does for the cache dirs (`--runtime-args -e --runtime-args VAR=value`). Not tested end to end locally.

| Variable | Fragment | Effect |
|---|---|---|
| `AGL_SSTATE_DIR` | `sstate-shared.yml` | shared sstate, split by `${DEFAULTTUNE}` |
| `AGL_DL_DIR` | `dl-shared.yml` | shared `DL_DIR` |
| `AGL_MIRROR_URL` | `mirrors.yml` | `PREMIRRORS` for git, gitsm, ftp, http, https to `$URL/dl/` and `SSTATE_MIRRORS` to `$URL/sstate/<tune>/`; AGL's own MIRRORS stay last. No trailing slash. The uninative tarball is found through the same line. |
| `AGL_HASHSERV_RW` (`host:port`) | `hashserv-rw.yml` | read **and write** shared hash server; trusted builds only |
| `AGL_HASHSERV_UPSTREAM` (`host:port`) | `hashserv-upstream.yml` | private local server reading a shared read-only upstream; for untrusted builds |

## Trust
- Downloads are checked against recipe checksums; **sstate objects have no integrity check.** Point `AGL_MIRROR_URL` only at a mirror that only trusted builds write.
- Anything that can write to the hash server can bind a task hash to an output of its choice: never give it to builds of fork pull requests.
- The AGL production mirror will be public; an OEM member can run a private one (different URL, own TLS/auth) with the same fragments. Nothing here may hard-code a host: the URL always comes from the variable. Do not commit a development mirror's address.

## Why `_RESOLVED`
Each fragment captures its variable with `:=` first; a direct reference in a lazy value arrives unexpanded (see `agl-ucb-kas-fragments`). Keep it.

## Offline and mirror drills
Proving a build survives without upstream (`BB_ALLOWED_NETWORKS`, fetch modes, filling the mirror, uninative) is agl-ci's job: skill `agl-ci-mirror-and-cache` and its manual chapter 15. Hash server operation: its chapter 14.
