#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
parts_dir="$repo_root/spec/parts"
index_file="$repo_root/spec/spec.md"

if [ ! -d "$parts_dir" ]; then
  echo "Missing spec parts directory: $parts_dir" >&2
  exit 1
fi

cat > "$index_file" <<'EOF'
# Spec Index

Canonical source:

- `spec/parts/`

Generated context slices:

EOF

while IFS= read -r part_file; do
  part_name=${part_file#"$repo_root/"}
  case "$part_name" in
    spec/parts/README.md)
      continue
      ;;
  esac
  printf -- '- [%s](./%s)\n' "$part_name" "${part_name#spec/}"
done < <(find "$parts_dir" -maxdepth 1 -type f -name '*.md' | sort) >> "$index_file"

cat >> "$index_file" <<'EOF'

The `spec/parts/` directory is the source of truth. Run `scripts/sync-spec.sh` to regenerate this index.
EOF

cat > "$parts_dir/README.md" <<'EOF'
# Split Spec Slices

These files are the canonical spec source.
Keep them updated directly; run `scripts/sync-spec.sh` to refresh `spec/spec.md`.
EOF
