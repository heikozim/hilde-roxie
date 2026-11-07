#!/usr/bin/env bash
# Runs inside the build container, from the root of a ROXIE tree beside a Wolly tree
# at $WOLLY_ROOT: compiles the programme roxie into _run/bin/roxie.  The
# modules are found by Wolly's scripts/modules.py, in the order of their
# imports.
# ROXIE_VERSION, when set, goes to the programme as
# --build-value=version=...; empty, the footer says dev.
#
#     WOLLY_ROOT=/path/wolly [ROXIE_VERSION=v0.1.0] bash scripts/in-build.sh
[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || { echo "ABORT: bash ${BASH_VERSION} too old" >&2; exit 9; }
set -u
[ -r /etc/wolly-dev ] || { echo "ABORT: not inside the build container -- nothing ran" >&2; exit 9; }
[ -d src/Roxie ] && [ -r app/App.hih ] || { echo "ABORT: run from the root of the ROXIE tree" >&2; exit 9; }
W=${WOLLY_ROOT:?WOLLY_ROOT names the Wolly tree}
[ -r "$W/scripts/modules.py" ] && [ -d "$W/src/Wolly" ] || { echo "ABORT: $W is no Wolly tree with scripts/modules.py" >&2; exit 9; }
mkdir -p _run/bin || exit 9
mods=$(python3 -I "$W/scripts/modules.py" /opt/hilde/standard/src /opt/hilde/bindings/generated "$W/src" src -- app/App.hih,app/App.hiq) || {
	echo "build: the modules were not found: $mods"
	exit 1
}
v=${ROXIE_VERSION:-}
[[ "$v" =~ ^[A-Za-z0-9.+-]{0,64}$ ]] || { echo "ABORT: ROXIE_VERSION of letters, digits, . + - only: $v" >&2; exit 9; }
value=()
[ -z "$v" ] || value=("--build-value=version=$v")
# shellcheck disable=SC2086
hilde compile $mods "${value[@]}" --entrypoint=Roxie.App:main --output=_run/bin/roxie
rc=$?
echo "build-rc=$rc ($(echo "$mods" | wc -w) modules)"
exit $rc
