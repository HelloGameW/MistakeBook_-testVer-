#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    printf '%s\n' '用法：sh Scripts/bump-version.sh bugfix|feature' >&2
    exit 2
fi

case "$1" in
    bugfix|feature) ;;
    *)
        printf '%s\n' '版本变更类型必须是 bugfix 或 feature。' >&2
        exit 2
        ;;
esac

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
config_path="$root_dir/Config/Shared.xcconfig"

old_version=$(awk -F' = ' '/^MARKETING_VERSION = / { print $2; exit }' "$config_path")
old_build=$(awk -F' = ' '/^CURRENT_PROJECT_VERSION = / { print $2; exit }' "$config_path")

case "$old_version" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) printf '%s\n' "无法解析 MARKETING_VERSION：$old_version" >&2; exit 1 ;;
esac
case "$old_build" in
    ''|*[!0-9]*) printf '%s\n' "无法解析 CURRENT_PROJECT_VERSION：$old_build" >&2; exit 1 ;;
esac

major=${old_version%%.*}
remainder=${old_version#*.}
minor=${remainder%%.*}
patch=${remainder#*.}

if [ "$1" = "feature" ]; then
    minor=$((minor + 1))
    patch=0
else
    patch=$((patch + 1))
fi

new_version="$major.$minor.$patch"
new_build=$((old_build + 1))
temporary_path="$config_path.tmp.$$"
trap 'rm -f "$temporary_path"' EXIT HUP INT TERM

awk -v version="$new_version" -v build="$new_build" '
    /^MARKETING_VERSION = / { print "MARKETING_VERSION = " version; next }
    /^CURRENT_PROJECT_VERSION = / { print "CURRENT_PROJECT_VERSION = " build; next }
    { print }
' "$config_path" > "$temporary_path"
mv "$temporary_path" "$config_path"
trap - EXIT HUP INT TERM

printf '版本：%s -> %s；构建号：%s -> %s\n' "$old_version" "$new_version" "$old_build" "$new_build"
