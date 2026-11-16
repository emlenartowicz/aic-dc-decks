#!/bin/bash
# publish.sh: copy the estate's built deck site into this repository and push it.
# Run only on Em's word. Usage:  ./publish.sh            (shows diff, asks before commit+push)
#                                ./publish.sh --dry-run  (copies + shows diff, commits nothing)
#
# The list of record is DC-Decks/site-manifest.txt (rewritten by every build.py run).
# Exactly the files it names are copied, byte for byte, and each is checked against the
# manifest's SHA-256 and size. site/assets/ and Finder litter are never published.
#
# Refuses to run if any file already published here is missing from the manifest:
# a printed QR code cannot change, so an address must never disappear. The one way past it is to
# name each such path, exactly, on Em's word:  ALLOW_REMOVE="a/b.pdf c/d.pptx" ./publish.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
SITE="${DECKS_SITE:-$REPO/../DC-Decks/site}"
MANIFEST="${DECKS_MANIFEST:-$REPO/../DC-Decks/site-manifest.txt}"
KEEP="publish.sh README.md .gitignore"   # repo-only files, not part of the site
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

[ -d "$SITE" ] || { echo "no site folder at $SITE" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "no manifest at $MANIFEST" >&2; exit 1; }
cd "$REPO"
git diff --quiet && git diff --cached --quiet || { echo "repository has uncommitted changes; stop" >&2; exit 1; }
git pull -q --ff-only origin main

want=$(awk '{p=$3; sub(/^\.\//,"",p); print p}' "$MANIFEST" | sort)

# 1. No published address may disappear.
missing=0; remove=""
while IFS= read -r p; do
  case " $KEEP " in *" $p "*) continue;; esac
  grep -qxF -- "$p" <<<"$want" && continue
  case " ${ALLOW_REMOVE:-} " in *" $p "*) remove="$remove $p"; continue;; esac
  echo "REFUSED: $p is published but not in the manifest" >&2; missing=1
done < <(git ls-files)
[ $missing -eq 0 ] || exit 2
for p in $remove; do echo "removing (named in ALLOW_REMOVE): $p"; git rm -q -- "$p"; done

# 2. Copy and verify each manifest file.
while read -r sha size path; do
  p="${path#./}"; src="$SITE/$p"
  [ -f "$src" ] || { echo "manifest names $p but $src is absent" >&2; exit 3; }
  got_sha=$(shasum -a 256 "$src" | cut -d' ' -f1); got_size=$(stat -f%z "$src")
  [ "$got_sha" = "$sha" ] && [ "$got_size" = "$size" ] || {
    echo "$p in site/ does not match the manifest (rebuilt since?). sha $got_sha size $got_size" >&2; exit 4; }
  mkdir -p "$(dirname "$p")"; cp -p "$src" "$p"
done < "$MANIFEST"

# 3. Mention anything in site/ the manifest leaves out (not published).
( cd "$SITE" && find . -type f ! -path './assets/*' ! -name .DS_Store | sed 's#^\./##' | sort ) \
  | comm -23 - <(echo "$want") | sed 's/^/note: in site\/ but not in manifest, not published: /'

git add -A -- $(echo "$want")
echo "---- changes ----"; git diff --cached --stat
if git diff --cached --quiet; then echo "nothing to publish"; exit 0; fi
undo(){ git reset -q --hard HEAD; git clean -fq -- $(echo "$want"); }  # back to HEAD exactly: the tree was clean when this run began (checked above), so all it holds is this run's copies
[ $DRY -eq 1 ] && { undo; echo "(dry run: nothing committed, tree restored)"; exit 0; }
read -r -p "Commit and push these to decks.aic-dc.net? [y/N] " ok
[ "$ok" = y ] || { undo; echo "not published, tree restored"; exit 0; }
git commit -q -m "Publish decks site ($(date -u +%Y-%m-%dT%H:%MZ))"
git push -q origin main
git log -1 --oneline
