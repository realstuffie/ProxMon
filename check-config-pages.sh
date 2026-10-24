#!/usr/bin/env bash
# Plasma injects every setting from contents/config/main.xml into every settings
# page as cfg_<name> and cfg_<name>Default. A page that does not declare one
# logs "Setting initial properties failed" when the dialog opens. This checks
# that every page declares all of them, so adding a setting without touching
# each page fails here and not on a user's screen.
set -u
cd "$(dirname "$0")" || exit 1

mapfile -t names < <(grep -o '<entry name="[A-Za-z0-9_]*"' contents/config/main.xml | cut -d'"' -f2)
status=0

for page in contents/ui/config*.qml; do
    missing=()
    for name in "${names[@]}"; do
        for suffix in "" "Default"; do
            if ! grep -qE "property +(alias|[A-Za-z]+) +cfg_${name}${suffix} *:" "$page"; then
                missing+=("cfg_${name}${suffix}")
            fi
        done
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        printf '%s is missing: %s\n' "$page" "${missing[*]}"
        status=1
    fi
done

if [ "$status" -eq 0 ]; then
    printf 'config pages OK (%d settings on each page)\n' "${#names[@]}"
fi
exit "$status"
