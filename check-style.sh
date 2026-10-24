#!/usr/bin/env bash
# Checks the whitespace rules in .editorconfig on every tracked text file.
#
#   - no tab characters
#   - no trailing whitespace
#   - shell scripts indent in multiples of 4 spaces, YAML in multiples of 2
#
# C++ and QML are not checked for the multiple-of-4 rule, because a continuation
# line lines up under the code above it and rarely lands on a multiple of 4.
# Heredoc bodies in shell scripts are printed as written, so they are skipped.
set -u
cd "$(dirname "$0")" || exit 1

status=0
report() {
    printf '%s\n' "$1"
    status=1
}

mapfile -d '' files < <(git ls-files -z -- . \
    ':(exclude)LICENSES' ':(exclude)License' ':(exclude)contents/lib/third_party' \
    ':(exclude).gitmodules' \
    ':(exclude)*.png' ':(exclude)*.svg' ':(exclude)*.ttf')

for file in "${files[@]}"; do
    [ -f "$file" ] || continue
    grep -qI . "$file" || continue   # skip binary files

    if grep -nP '\t' "$file" >/dev/null; then
        report "$file: contains tab characters (lines: $(grep -nP '\t' "$file" | cut -d: -f1 | head -5 | tr '\n' ' '))"
    fi
    if grep -nP '[ \t]+$' "$file" >/dev/null; then
        report "$file: trailing whitespace (lines: $(grep -nP '[ \t]+$' "$file" | cut -d: -f1 | head -5 | tr '\n' ' '))"
    fi

    step=0
    case "$file" in
        *.sh) step=4 ;;
        *.yml|*.yaml) step=2 ;;
    esac
    if [ "$step" -ne 0 ]; then
        bad=$(awk -v step="$step" '
            heredoc != "" { if ($0 == heredoc) heredoc = ""; next }
            /[^ ]/ {
                match($0, /^ */)
                if (RLENGTH % step != 0) printf "%d ", NR
            }
            match($0, /<<-?[ ]*["\047]?[A-Za-z_]+/) {
                tag = substr($0, RSTART, RLENGTH)
                gsub(/<<-?[ ]*["\047]?/, "", tag)
                heredoc = tag
            }
        ' "$file")
        if [ -n "$bad" ]; then
            report "$file: indent is not a multiple of $step (lines: ${bad:0:60})"
        fi
    fi
done

if [ "$status" -eq 0 ]; then
    printf 'style check passed (%d files)\n' "${#files[@]}"
fi
exit "$status"
