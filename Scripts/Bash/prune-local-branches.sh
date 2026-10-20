#!/usr/bin/env bash

# Script that deletes local branches that were merged on remote, in every git
# repo found directly under a root folder.
# author: @victormarcias
#
# Usage: prune-local-branches.sh [-n] [-y] [root]
#   -n    dry run: only list what would be deleted
#   -y    don't ask for confirmation before deleting
#   root  folder that contains the repos (default: ~/Documents/GitHub)

set -u

PROTECTED_BRANCHES='main|master|develop'
DRY_RUN=false
ASSUME_YES=false

function goneBranches {
    # A branch is 'gone' when its upstream was deleted in origin (usually
    # because the PR was merged). for-each-ref is stable, unlike parsing
    # `git branch -vv`, and it doesn't depend on the remote being 'origin'.
    git for-each-ref --format='%(refname:short)|%(upstream:track)' refs/heads \
        | awk -F'|' '$2 == "[gone]" {print $1}' \
        | grep -Ev "^($PROTECTED_BRANCHES)$"
}

function pruneLocalBranches {
    # Fetching first: if it fails (offline, no access) nothing gets deleted
    if ! git fetch --prune origin > /dev/null 2>&1
    then
        printf '⚠️ - Could not fetch origin, skipping.\n'
        return
    fi

    local current branches answer branch
    current=$(git symbolic-ref --short -q HEAD)
    branches=$(goneBranches)

    # The checked out branch can't be deleted
    if [ -n "$current" ] && grep -qx -- "$current" <<< "$branches"
    then
        printf '⏭️ - Keeping checked out branch \033[1;33m%s\033[0m.\n' "$current"
        branches=$(grep -vx -- "$current" <<< "$branches")
    fi

    if [ -z "$branches" ]
    then
        printf '✨ - Nothing to prune.\n'
        return
    fi

    # `git branch -D` is needed because squash merges are never "merged" for
    # git, but it also means a branch deleted in origin WITHOUT being merged
    # loses its local commits. That's why we show the list first.
    printf '%s\n' "$branches" | sed 's/^/   - /'
    $DRY_RUN && return

    if ! $ASSUME_YES
    then
        read -r -p "   Delete these branches? [y/N] " answer
        [[ "$answer" =~ ^[Yy]$ ]] || return
    fi

    # Git prints the sha of each deleted branch: `git branch <name> <sha>`
    # (or the reflog) brings it back if it was a mistake.
    while IFS= read -r branch
    do
        git branch -D "$branch"
    done <<< "$branches"
}

# Every direct subfolder of the root that is a git repo with an origin
function pruneMergedBranchesInDir {
    local dir=$1

    [ -e "$dir/.git" ] || return
    git -C "$dir" remote get-url origin > /dev/null 2>&1 || return

    printf '🔥 - Pruning \033[1;37m%s\033[0m local branches.\n' "$(basename "$dir")"
    # Subshell, so a failure never leaves us in the wrong folder
    (cd "$dir" && pruneLocalBranches)
}

while getopts 'ny' option
do
    case $option in
        n) DRY_RUN=true ;;
        y) ASSUME_YES=true ;;
        *) exit 1 ;;
    esac
done
shift $((OPTIND - 1))

ROOT=${1:-$HOME/Documents/GitHub}

if [ ! -d "$ROOT" ]
then
    printf '⚠️ - Directory \033[1;31m%s\033[0m not found.\n' "$ROOT"
    exit 1
fi

for dir in "$ROOT"/*/
do
    pruneMergedBranchesInDir "${dir%/}"
done
