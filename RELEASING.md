# Releasing

The updater (`install.sh --update`) reads `VERSION` on the `main` branch and downloads the
archive of the tag `vX.Y.Z`, so both must exist and agree.

1. Change the version in `VERSION`, `lock-guard`, `randr-fix` and `install.sh` (the tests check that
   all four match: `sh test/test.sh`).
2. Add the entry to `CHANGELOG.md`.
3. Run the tests under dash, bash and busybox sh, and `shellcheck -s sh lock-guard randr-fix install.sh`.
4. Commit to `main`, then `git tag vX.Y.Z && git push origin main vX.Y.Z`.

Push the tag **before or together with** the commit that changes `VERSION`: if `VERSION` is ahead
of the tag, `--update` finds a version whose archive does not exist yet and fails with a download
error (nothing is changed).
