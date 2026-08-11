#!/bin/sh
# Formats and lints Python (ruff) and Swift (swift-format).
# With no arguments, covers every non-ignored file in the repo; otherwise only
# the files given.
set -eu

repo_root=$(cd "$(dirname "$0")" && pwd)

if [ "$#" -eq 0 ]; then
    whole_repo=1
    # shellcheck disable=SC2046
    set -- $(git -C "$repo_root" ls-files --cached --others --exclude-standard | sed "s|^|$repo_root/|")
else
    whole_repo=0
fi

py_files=""
swift_files=""

for file in "$@"; do
    case "$file" in
        /*) path="$file" ;;
        *) path="$PWD/$file" ;;
    esac

    # a tracked file can be missing from the worktree because it was deleted,
    # which is only a mistake if the caller named it themselves
    if [ ! -f "$path" ]; then
        [ "$whole_repo" -eq 1 ] || { echo "format.sh: no such file: $file" >&2; exit 1; }
        continue
    fi

    case "$path" in
        *.py) py_files="$py_files $path" ;;
        *.swift) swift_files="$swift_files $path" ;;
        *) [ "$whole_repo" -eq 1 ] || echo "format.sh: no formatter for $file" >&2 ;;
    esac
done

status=0

if [ -n "$py_files" ]; then
    # shellcheck disable=SC2086
    uv run --project "$repo_root/server" ruff format -- $py_files || status=1
    # shellcheck disable=SC2086
    uv run --project "$repo_root/server" ruff check --fix -- $py_files || status=1
fi

if [ -n "$swift_files" ]; then
    # shellcheck disable=SC2086
    xcrun swift-format format --in-place -- $swift_files || status=1
    # shellcheck disable=SC2086
    xcrun swift-format lint -- $swift_files || status=1
fi

exit $status
