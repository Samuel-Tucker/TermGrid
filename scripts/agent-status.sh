#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

git -C "$ROOT_DIR" rev-parse --show-toplevel >/dev/null

printf 'repo: %s\n\n' "$ROOT_DIR"

while IFS= read -r line; do
    [ -n "$line" ] || continue

    path="${line%% *}"
    branch_part="${line#*[}"
    branch="${branch_part%]*}"

    printf 'worktree: %s\n' "$path"
    printf 'branch:   %s\n' "$branch"

    if git -C "$path" diff --quiet && git -C "$path" diff --cached --quiet; then
        printf 'state:    clean\n'
    else
        printf 'state:    dirty\n'
    fi

    changed="$(git -C "$path" status --short)"
    if [ -n "$changed" ]; then
        printf 'changes:\n'
        printf '%s\n' "$changed" | sed 's/^/  /'
    else
        printf 'changes:  none\n'
    fi

    printf '\n'
done < <(git -C "$ROOT_DIR" worktree list --porcelain | awk '
    /^worktree / { wt=$2 }
    /^branch / {
        sub("refs/heads/", "", $2)
        print wt " [" $2 "]"
    }
')
