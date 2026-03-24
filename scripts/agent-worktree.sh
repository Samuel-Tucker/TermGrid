#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKTREE_ROOT="$ROOT_DIR/.worktrees"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/agent-worktree.sh create <task-name> [base-ref]
  ./scripts/agent-worktree.sh list
  ./scripts/agent-worktree.sh path <task-name>
  ./scripts/agent-worktree.sh remove <task-name>
  ./scripts/agent-worktree.sh prune

Creates isolated git worktrees for parallel agent or worker tasks.
Branch names use: agent/<task-name>
Worktree paths use: .worktrees/<task-name>
EOF
}

require_repo() {
    git -C "$ROOT_DIR" rev-parse --show-toplevel >/dev/null
}

sanitize_name() {
    local raw="$1"
    local lowered
    lowered="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
    local cleaned
    cleaned="$(printf '%s' "$lowered" | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
    if [ -z "$cleaned" ]; then
        echo "error: task name produced an empty slug" >&2
        exit 1
    fi
    printf '%s\n' "$cleaned"
}

branch_name_for() {
    printf 'agent/%s\n' "$1"
}

path_for() {
    printf '%s/%s\n' "$WORKTREE_ROOT" "$1"
}

create_worktree() {
    local slug
    slug="$(sanitize_name "$1")"
    local base_ref="${2:-HEAD}"
    local branch
    branch="$(branch_name_for "$slug")"
    local worktree_path
    worktree_path="$(path_for "$slug")"

    mkdir -p "$WORKTREE_ROOT"

    if [ -e "$worktree_path" ]; then
        echo "error: worktree already exists at $worktree_path" >&2
        exit 1
    fi

    if git -C "$ROOT_DIR" show-ref --verify --quiet "refs/heads/$branch"; then
        git -C "$ROOT_DIR" worktree add "$worktree_path" "$branch"
    else
        git -C "$ROOT_DIR" worktree add -b "$branch" "$worktree_path" "$base_ref"
    fi

    cat <<EOF
created worktree
path: $worktree_path
branch: $branch
base: $base_ref

next:
  cd "$worktree_path"
  swift test --filter <relevant-suite>
EOF
}

list_worktrees() {
    git -C "$ROOT_DIR" worktree list
}

print_path() {
    local slug
    slug="$(sanitize_name "$1")"
    path_for "$slug"
}

remove_worktree() {
    local slug
    slug="$(sanitize_name "$1")"
    local worktree_path
    worktree_path="$(path_for "$slug")"

    if [ ! -d "$worktree_path" ]; then
        echo "error: no worktree found at $worktree_path" >&2
        exit 1
    fi

    git -C "$ROOT_DIR" worktree remove "$worktree_path"
    echo "removed: $worktree_path"
    echo "branch retained: $(branch_name_for "$slug")"
}

prune_worktrees() {
    git -C "$ROOT_DIR" worktree prune
    echo "pruned stale worktree metadata"
}

main() {
    require_repo

    local command="${1:-}"
    case "$command" in
        create)
            [ $# -ge 2 ] || { usage >&2; exit 1; }
            create_worktree "$2" "${3:-HEAD}"
            ;;
        list)
            list_worktrees
            ;;
        path)
            [ $# -ge 2 ] || { usage >&2; exit 1; }
            print_path "$2"
            ;;
        remove)
            [ $# -ge 2 ] || { usage >&2; exit 1; }
            remove_worktree "$2"
            ;;
        prune)
            prune_worktrees
            ;;
        -h|--help|help|"")
            usage
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
