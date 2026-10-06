#!/usr/bin/env bash
# Opens the "Publish X.Y.Z to Figma Community" issue for a release: Figma has
# no API to publish a plugin, so this is the one release step done by hand,
# in the Figma desktop app. The issue has the steps and the version note.
#
#   tool/figma_publish_issue.sh <tag> <changes.md> [--dry-run]
#
# <changes.md> is the version's CHANGELOG.md section. --dry-run prints the
# issue instead of creating it. Called by .github/workflows/release-plugin.yml.
set -euo pipefail

tag=$1
changes=$2
dry_run=${3:-}
version=${tag#v}
repo=${GITHUB_REPOSITORY:-CarlosMarioM/flutter2figma}
title="Publish $version to Figma Community"
zip="https://github.com/$repo/releases/download/$tag/flutter2figma-figma-plugin-$version.zip"

# Network access and permissions are declared in manifest.json: when it
# changed, Figma's data-security answers may have too.
manifest_note=""
previous=$(git describe --tags --abbrev=0 "$tag^" 2>/dev/null || true)
if [ -n "$previous" ] && ! git diff --quiet "$previous" "$tag" -- figma-plugin/manifest.json; then
  manifest_note="
> [!WARNING]
> \`figma-plugin/manifest.json\` changed since $previous. Re-check the
> data-security answers in \`figma-plugin/listing/LISTING.md\` before
> submitting.
"
fi

body=$(cat <<EOF
Figma has no API for publishing plugins, so this release step is done by hand
in the Figma desktop app. Everything else about $tag is already released.
$manifest_note
- [ ] Download and unzip [flutter2figma-figma-plugin-$version.zip]($zip).
- [ ] In Figma: **Plugins → Development → Import plugin from manifest…** with
      its \`manifest.json\` (or replace the files of the development plugin
      you publish from).
- [ ] Run it once on a \`design.json\` exported by flutter2figma $version.
- [ ] **Plugins → Development → Flutter2Figma → Publish**: publish a new
      version with the note below. Figma reviews it before it goes live.
- [ ] Close this issue once Figma approves it.

### Version note

\`\`\`
$(sed -e '/./,$!d' "$changes")
\`\`\`
EOF
)

if [ "$dry_run" = --dry-run ]; then
  printf '# %s\n\n%s\n' "$title" "$body"
  exit 0
fi

# Once per version: re-running the release workflow doesn't open another.
if gh issue list --repo "$repo" --state all --search "\"$title\" in:title" \
  --json title --jq '.[].title' | grep -Fxq "$title"; then
  echo "Issue \"$title\" already exists."
  exit 0
fi
gh issue create --repo "$repo" --title "$title" --body "$body"
