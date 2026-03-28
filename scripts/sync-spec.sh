#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_spec="$repo_root/spec/source.md"
out_dir="$repo_root/spec/parts"

if [ ! -f "$source_spec" ]; then
  echo "Missing spec source: $source_spec" >&2
  exit 1
fi

rm -rf "$out_dir"
mkdir -p "$out_dir"

awk -v out_dir="$out_dir" '
function slugify(text, s) {
  s = text
  sub(/^##[[:space:]]+/, "", s)
  sub(/^[0-9]+(\.[0-9]+)*[ .]+/, "", s)
  gsub(/[`"]/, "", s)
  gsub(/[^[:alnum:]]+/, "-", s)
  gsub(/^-+|-+$/, "", s)
  s = tolower(s)
  if (s == "") {
    s = "section"
  }
  return s
}

function open_section(title, section_number, file) {
  file = sprintf("%s/%02d-%s.md", out_dir, section_number, slugify(title))
  return file
}

BEGIN {
  section_index = 0
  current_file = sprintf("%s/00-overview.md", out_dir)
}

{
  if ($0 ~ /^##[[:space:]]+/) {
    section_index++
    current_file = open_section($0, section_index)
  }

  print $0 >> current_file
}
' "$source_spec"

cat > "$out_dir/README.md" <<EOF
# Split Spec Slices

This directory is generated from \`spec/source.md\` by \`scripts/sync-spec.sh\`.
Use the numbered markdown files here when you want smaller context chunks.
EOF
