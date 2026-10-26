#!/usr/bin/env bash
# Builds dist/proxmon-<version>.tar.gz and its .sha256 from the tracked files.
# git archive leaves submodules out, so the file list comes from
# git ls-files --recurse-submodules, which includes the qtkeychain sources.
#
# Usage: ./make-dist.sh [version]    (default: the Version in metadata.json)
set -euo pipefail
cd "$(dirname "$0")"

version="${1:-$(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' metadata.json)}"
if [ -z "$version" ]; then
    printf '%s\n' "Could not read the version from metadata.json." >&2
    exit 1
fi

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    printf '%s\n' "Uncommitted changes in tracked files. Commit them first." >&2
    exit 1
fi

# The tarball has to match the release, so refuse when the tag points elsewhere.
if git rev-parse -q --verify "refs/tags/v$version" >/dev/null \
    && [ "$(git rev-parse HEAD)" != "$(git rev-parse "v$version^{commit}")" ]; then
    printf '%s\n' "HEAD is not at tag v$version. Check out the tag first." >&2
    exit 1
fi

name="proxmon-$version"
tarball="dist/$name.tar.gz"
mkdir -p dist

# Sorted names, fixed owner and the commit time keep the tarball reproducible.
git ls-files -z --recurse-submodules \
    | tar --null -T - --transform "s,^,$name/," --sort=name \
        --owner=0 --group=0 --numeric-owner \
        --mtime="@$(git log -1 --format=%ct)" -cf - \
    | gzip -n > "$tarball"

(cd dist && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
printf '%s\n' "Wrote $tarball ($(du -h "$tarball" | cut -f1))"
cat "$tarball.sha256"
