#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/.codex/skills"

usage() {
    cat <<'EOF'
Usage: ./scripts/install-repo-skills.sh [codex|claude|all]

Symlinks repo-local skills from .codex/skills into one or both home skill directories.
Defaults to: all
EOF
}

link_skill_set() {
    local target_root="$1"
    local target_dir="$target_root/skills"

    mkdir -p "$target_dir"

    local linked=0
    local skipped=0
    local skill_dir
    for skill_dir in "$SOURCE_DIR"/*; do
        [ -d "$skill_dir" ] || continue

        local name
        name="$(basename "$skill_dir")"
        local dest="$target_dir/$name"

        if [ -e "$dest" ] && [ ! -L "$dest" ]; then
            echo "skip: $dest exists and is not a symlink"
            skipped=$((skipped + 1))
            continue
        fi

        rm -f "$dest"
        ln -s "$skill_dir" "$dest"
        echo "linked: $dest -> $skill_dir"
        linked=$((linked + 1))
    done

    echo "summary: linked $linked skill(s), skipped $skipped in $target_dir"
}

main() {
    if [ ! -d "$SOURCE_DIR" ]; then
        echo "error: source directory not found: $SOURCE_DIR" >&2
        exit 1
    fi

    local mode="${1:-all}"
    case "$mode" in
        codex)
            link_skill_set "${CODEX_HOME:-$HOME/.codex}"
            ;;
        claude)
            link_skill_set "${CLAUDE_HOME:-$HOME/.claude}"
            ;;
        all)
            link_skill_set "${CODEX_HOME:-$HOME/.codex}"
            link_skill_set "${CLAUDE_HOME:-$HOME/.claude}"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
