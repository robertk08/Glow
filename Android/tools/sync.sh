#!/usr/bin/env bash
set -euo pipefail

cd "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"

fail() {
  echo "" >&2
  echo "!!! SYNC FAILED: $*" >&2
  echo "!!! Nothing was forced. Fix this before committing, pushing or flashing." >&2
  exit 1
}

if [[ -d "$(git rev-parse --git-path rebase-merge)" || -d "$(git rev-parse --git-path rebase-apply)" ]]; then
  fail "a rebase is in progress. Resolve it or run git rebase --abort."
fi

if [[ "$(git branch --show-current)" != main ]]; then
  fail "not on main"
fi

git fetch --quiet origin || fail "git fetch origin"

marker="$(git rev-parse --git-path glow-synced)"
if [[ -f "$marker" ]] && git cat-file -e "$(cat "$marker")^{commit}" 2>/dev/null; then
  seen="$(cat "$marker")"
else
  seen="$(git rev-parse HEAD)"
fi

tracked=()
added=()
while IFS= read -r -d '' status && IFS= read -r -d '' path; do
  if [[ "$status" == A ]]; then
    added+=("$path")
  else
    tracked+=("$path")
  fi
done < <(git diff --no-renames --name-status -z HEAD -- ':(top,exclude)Android')

if (( ${#tracked[@]} )); then
  echo "Discarding changes outside Android/, they must never happen here:"
  printf '  %s\n' "${tracked[@]}"
  git restore --source=HEAD --staged --worktree -- "${tracked[@]}" || fail "git restore"
fi

if (( ${#added[@]} )); then
  echo "Unstaging new files outside Android/, they stay on disk:"
  printf '  %s\n' "${added[@]}"
  git restore --staged -- "${added[@]}" || fail "git restore --staged"
fi

untracked="$(git ls-files --others --exclude-standard -- ':(top,exclude)Android')"
if [[ -n "$untracked" ]]; then
  echo "Untracked files outside Android/ (left alone, remove them yourself):"
  sed 's/^/  /' <<< "$untracked"
fi

git pull --quiet --rebase --autostash origin main || fail "git pull --rebase --autostash"

upstream="$(git rev-parse origin/main)"
if [[ "$seen" != "$upstream" ]]; then
  echo "New on origin/main:"
  git log --oneline --no-decorate "$seen..$upstream" | sed 's/^/  /'
  protocol="$(git diff --name-only "$seen" "$upstream" -- README.md Glow/Controller Glow/Shows Arduino)"
  if [[ -n "$protocol" ]]; then
    echo ""
    echo "*** PROTOCOL OR FIRMWARE CHANGED. Check the Android app against: ***"
    sed 's/^/  /' <<< "$protocol"
  fi
fi
echo "$upstream" > "$marker"

ahead="$(git rev-list --count origin/main..HEAD)"
echo "In sync with origin/main $(git rev-parse --short origin/main), $ahead local commit(s) to push."
