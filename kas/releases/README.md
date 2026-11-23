# kas/releases: the pins of each release

One file per release: `pins_<branch>_<version>.yml`, for example `pins_vimba_22.0.2.yml`. It pins **every** repo that any fragment of `kas/`
defines, including `meta-agl`, `meta-agl-demo` and `meta-agl-devel`, each at one commit. It has the format of `kas/pins.yml`.

- **How it is made**: `scripts/prepare-release.sh <branch> <version>` (see the comment at its top). Review the file, commit it, merge it
  by pull request, then a release engineer creates the tag `<branch>_<version>` on the merge commit. The tag starts the release build
  of agl-ci (`release.yml`), which uses this file **instead of** `kas/pins.yml`.
- **Never edit one, never reuse a version.** A release is rebuilt years later from its file; a changed file would break that. A fix is a new version.
- **Why the layers are in these files but not in `kas/pins.yml`**: in `kas/pins.yml` a pin of a layer would beat the generated pin of the repo
  under test in a pull request build (kas applies `overrides:` last). A release build has no repo under test.
- `scripts/check-kas.py` checks the name and that every commit is a 40-hex SHA.
- The countersignature of the release engineer is committed here too: `<branch>_<version>.SHA256SUMS.<id>.sig` (added after the tag; it does
  not change the tagged commit).
