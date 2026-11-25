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

## What happens after the tag
The tag (`<branch>_<version>`, regex `^[a-z]+_[0-9]+\.[0-9]+\.[0-9]+$`; only repository admins can create it: ruleset "release tags") starts
`.github/workflows/release.yml` of this repo, which calls the reusable workflow of agl-ci (pinned by commit; bump the pin by pull request). The caller grants
`contents: write` and `id-token: write` (the ceiling; the called workflow uses `id-token` in its signing job only and `contents: write` in its publish job only):

1. every image of the tier `release` is built, in parallel, on any host of the pool, with this pins file instead of `kas/pins.yml`;
2. the signing job checks each kas statement against this file and signs; the publish job creates the GitHub release of the tag with the signed files;
3. the download server pulls the images of all build hosts, fetches the signed files and waits for the engineer signature below.

## Signing as a release engineer
After the run is green (about 20 minutes with a warm cache), download `SHA256SUMS` and `SHA256SUMS.bundle` from the GitHub release of the tag, verify the CI
signature, sign `SHA256SUMS` with your token and add the file here by pull request:
```bash
cosign sign-blob --sk --output-signature kas/releases/<branch>_<version>.SHA256SUMS.<id>.sig SHA256SUMS
```
Your public key must be in agl-ci `keys/release/<id>.pub`. The download server pulls this repo every five minutes, counts the signature, checks every hash and
promotes the release. The complete description, the verification commands for users and the failures seen in the rehearsal are in agl-ci, manual chapter 19.
