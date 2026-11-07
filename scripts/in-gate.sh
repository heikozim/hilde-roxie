#!/usr/bin/env bash
# Runs inside the build container, from the root of a ROXIE tree beside a Wolly tree
# at $WOLLY_ROOT: the gate of ROXIE.
#
#   1. the unit tests of src, all of them;
#   2. hilde test --contracts over each module with contracts, the module
#      alone in a directory of its own, seed and rounds fixed; before
#      that, scripts/check-contracts.pl over src and app, its self-test
#      first: every public function states a contract or the line
#      "No contract: <reason>." in its docstring, a miss fails the gate;
#   3. with WOLLY_MUTATE=1 only:
#      every mutation of scripts/mutations-*.sh, each in a copy of src,
#      against the unit test of the module it breaks.  A mutation that
#      changes nothing, or does not build, is BROKEN, one the test does not
#      notice MISSED;
#   4. the programme built (scripts/in-build.sh) and its end-to-end run
#      behind Hiawatha with TLS (scripts/in-e2e.sh).
#
# The parts are jobs that share nothing but the tree they read:
# the unit tests, each module's contracts, each mutation in a copy of its
# own, and the build; the end-to-end run of what the build made runs after
# all of them, alone, as its checks wait with time limits.
# GATE_JOBS of them run at once (default: the number of processors, 1 is
# the order below one after the other); each writes its lines and its exit
# into $RUN/jobs, and the lines are printed afterwards in the order of the
# parts above, whatever the order the jobs ended in.  What each job took
# goes into $RUN/times, not into the output, so that a run with one job
# and a run with many print the same bytes.  Ends with one line of counts;
# exit 0 only when every part is green.
#
#     WOLLY_ROOT=/path/wolly [GATE_JOBS=16] [WOLLY_MUTATE=1] bash scripts/in-gate.sh
[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || { echo "ABORT: bash ${BASH_VERSION} too old" >&2; exit 9; }
set -u
[ -r /etc/wolly-dev ] || { echo "ABORT: not inside the build container -- nothing ran" >&2; exit 9; }
[ -d src/Roxie ] || { echo "ABORT: run from the root of the ROXIE tree" >&2; exit 9; }
[ -r app/App.hih ] || { echo "ABORT: no app/App.hih -- run from the root of the ROXIE tree" >&2; exit 9; }
W=${WOLLY_ROOT:?WOLLY_ROOT names the Wolly tree}/src
[ -d "$W/Wolly" ] || { echo "ABORT: $W holds no Wolly" >&2; exit 9; }
BASE=/opt/hilde/bindings/generated:/opt/hilde/standard/src:$W
RUN=${RUN:-/tmp/roxie-gate}
SEED=20261015 ROUNDS=1000

mutations=()
shell_mutations=()
for f in scripts/mutations-*.sh; do
	[ -r "$f" ] || continue
	# shellcheck disable=SC1090
	. "$f"
done
# The mutations are read always, so that a file of them that is broken
# stops every gate; they run only with WOLLY_MUTATE=1.
case "${WOLLY_MUTATE:-0}" in
1) nm=${#mutations[@]} ns=${#shell_mutations[@]} ;;
0) nm=0 ns=0 ;;
*) echo "ABORT: WOLLY_MUTATE is 0 or 1, not $WOLLY_MUTATE" >&2; exit 9 ;;
esac
contracted=()
for hih in src/Roxie/*.hih; do
	grep -q -E '^[[:space:]]+(requires|ensures) ' "$hih" && contracted+=("$(basename "$hih" .hih)")
done

# --- one job: its lines on the standard output, its verdict as the exit --
unit_job() {
	hilde test --modules="$BASE" src > "$RUN/unit.log" 2>&1
	local unit=$?
	tail -2 "$RUN/unit.log"
	echo "unit-rc=$unit"
	return $unit
}

contract_lint_job() {
	perl scripts/check-contracts.pl --self-test || return 1
	perl scripts/check-contracts.pl src app
}

contracts_job() {
	local m=$1 c=$RUN/contracts-$1 r
	mkdir -p "$c/one/Roxie" "$c/rest" || return 9
	cp -r src/Roxie "$c/rest/" || return 9
	mv "$c/rest/Roxie/$m.hih" "$c/rest/Roxie/$m.hiq" "$c/one/Roxie/" || return 9
	rm -f "$c/rest/Roxie/$m.test.hiq"
	# The templates of a module are found beside it (@template).
	[ ! -d src/Roxie/templates ] || cp -r src/Roxie/templates "$c/one/Roxie/" || return 9
	hilde test --contracts --seed=$SEED --rounds=$ROUNDS --modules="$BASE:$c/rest" "$c/one" > "$c.log" 2>&1
	r=$?
	echo "contracts $m rc=$r $(grep -E '^(ok|FAIL) ' "$c.log" | tail -1)"
	return $r
}

# The exit of a mutation job: 0 caught, 1 missed, 2 broken, 9 not run.
mutation_job() {
	local m=${mutations[$1]} copy=$RUN/mutant-$1
	local file=${m%%|*} rest=${m#*|}
	local expr=${rest%|*} what=${rest##*|}
	rm -rf "$copy" && mkdir -p "$copy" && cp -r src "$copy/" || return 9
	sed -i -e "$expr" "$copy/src/Roxie/$file" || { echo "BROKEN  $what (sed)"; return 2; }
	if cmp -s "src/Roxie/$file" "$copy/src/Roxie/$file"; then
		echo "BROKEN  $what (nothing changed)"
		return 2
	fi
	local test=$copy/src/Roxie/${file%.*}.test.hiq
	[ -r "$test" ] || { echo "BROKEN  $what (no test file)"; return 2; }
	if hilde test --modules="$BASE:$copy/src" "$test" > "$copy.log" 2>&1; then
		echo "MISSED  $what"
		return 1
	elif grep -q "did not build" "$copy.log"; then
		# A mutant that does not build tells nothing of the tests.
		echo "BROKEN  $what (the mutant does not build)"
		return 2
	else
		echo "caught  $what ($(grep -c -E 'FAIL|failed' "$copy.log") lines of failure)"
		return 0
	fi
}

shell_mutation_job() {
	local m=${shell_mutations[$1]} copy=$RUN/shellmut-$1
	local file=${m%%|*} rest=${m#*|}
	local expr=${rest%|*} what=${rest##*|}
	rm -rf "$copy" && mkdir -p "$copy" && cp -r deploy scripts "$copy/" || return 9
	perl -i -pe "$expr" "$copy/$file" || { echo "BROKEN  $what (perl)"; return 2; }
	if cmp -s "$file" "$copy/$file"; then
		echo "BROKEN  $what (nothing changed)"
		return 2
	fi
	if (cd "$copy" && bash scripts/in-test-edge-pull.sh) > "$copy.log" 2>&1; then
		echo "MISSED  $what"
		return 1
	fi
	echo "caught  $what ($(grep -c '^FAIL' "$copy.log") failing)"
	return 0
}

# The build: a job beside the others.
build_job() {
	# The build is given a version as build-binary.sh gives a tag, so the end
	# to end run reads the footer through Standard.BuildInfo.
	ROXIE_VERSION=v9.8.7-3-gabcdef1 bash scripts/in-build.sh > "$RUN/build.log" 2>&1
	local build=$?
	tail -1 "$RUN/build.log"
	return $build
}

# The end-to-end run of what the build made: after every other job, alone.
# Its checks wait for Hiawatha and for answers with time limits, and beside
# a full machine Hiawatha was not up in time (measured:
# 107 of 155 at status 000); alone it sees what the serial run saw.  A red
# run also prints whether the socket and Hiawatha were up and what Hiawatha
# wrote, as a gate on a server was red with 108 of 159
# failing, 62 of them at status 000, and its log said nothing more; a green run prints the same
# bytes as before.
e2e_job() {
	bash scripts/in-e2e.sh > "$RUN/e2e.log" 2>&1
	local e2e=$?
	grep -E "^FAIL" "$RUN/e2e.log"
	if [ $e2e -ne 0 ]; then
		grep -E "^(roxie-socket|hiawatha-alive)=" "$RUN/e2e.log"
		echo "== hiawatha.out"
		head -20 _run/e2e/hiawatha.out 2> /dev/null
	fi
	tail -1 "$RUN/e2e.log"
	return $e2e
}

if [ "${1:-}" = --job ]; then
	name=$2
	start=$(date +%s%N)
	case "$name" in
	unit) unit_job ;;
	contract-lint) contract_lint_job ;;
	contracts-*) contracts_job "${name#contracts-}" ;;
	mutation-*) mutation_job "${name#mutation-}" ;;
	shellmut-*) shell_mutation_job "${name#shellmut-}" ;;
	build) build_job ;;
	e2e) e2e_job ;;
	*) echo "ABORT: no job $name"; exit 9 ;;
	esac > "$RUN/jobs/$name.out" 2>&1
	echo $? > "$RUN/jobs/$name.rc"
	echo "$name $(( ($(date +%s%N) - start) / 1000000 ))" > "$RUN/times/$name"
	exit 0
fi

rm -rf "$RUN" && mkdir -p "$RUN/jobs" "$RUN/times" || exit 9
jobs=${GATE_JOBS:-$(nproc)}
[[ "$jobs" =~ ^[1-9][0-9]{0,2}$ ]] || { echo "ABORT: GATE_JOBS is no number of 1 to 999: $jobs" >&2; exit 9; }
# The longest first: the build, the unit tests, then the mutations and the
# contracts; the end-to-end run after them.
{
	echo build
	echo unit
	for ((i = 0; i < nm; i++)); do echo "mutation-$i"; done
	for m in "${contracted[@]}"; do echo "contracts-$m"; done
	echo contract-lint
	for ((i = 0; i < ns; i++)); do echo "shellmut-$i"; done
} > "$RUN/order"
start=$(date +%s%N)
xargs -P "$jobs" -I{} bash "$0" --job {} < "$RUN/order"
build=$(cat "$RUN/jobs/build.rc" 2> /dev/null || echo 9)
if [ "$build" -eq 0 ]; then
	bash "$0" --job e2e
	echo e2e >> "$RUN/order"
fi
echo "gate jobs=$jobs wall-ms=$(( ($(date +%s%N) - start) / 1000000 ))" > "$RUN/times/gate"
missing=0
while read -r name; do
	[ -r "$RUN/jobs/$name.rc" ] || { echo "ABORT: the job $name left no exit"; missing=$((missing + 1)); }
done < "$RUN/order"
[ "$missing" -eq 0 ] || exit 9
rc() { cat "$RUN/jobs/$1.rc"; }

# --- the lines, in the order of the parts --------------------------------
cat "$RUN/jobs/unit.out"
unit=$(rc unit)
cat "$RUN/jobs/contract-lint.out"
lint=$(rc contract-lint)
contracts=0
[ "$lint" -eq 0 ] || contracts=1
for m in "${contracted[@]}"; do
	cat "$RUN/jobs/contracts-$m.out"
	[ "$(rc "contracts-$m")" -eq 0 ] || contracts=1
done
echo "contracts-rc=$contracts lint-rc=$lint modules=${#contracted[@]}"
caught=0 missed=0 broken=0
for ((i = 0; i < nm; i++)); do
	cat "$RUN/jobs/mutation-$i.out"
	case "$(rc "mutation-$i")" in
	0) caught=$((caught + 1)) ;;
	1) missed=$((missed + 1)) ;;
	2) broken=$((broken + 1)) ;;
	*) echo "ABORT: mutation $i did not run"; exit 9 ;;
	esac
done
for ((i = 0; i < ns; i++)); do
	cat "$RUN/jobs/shellmut-$i.out"
	case "$(rc "shellmut-$i")" in
	0) caught=$((caught + 1)) ;;
	1) missed=$((missed + 1)) ;;
	2) broken=$((broken + 1)) ;;
	*) echo "ABORT: shell mutation $i did not run"; exit 9 ;;
	esac
done
cat "$RUN/jobs/build.out"
build=$(rc build) e2e=9
if [ "$build" -eq 0 ]; then
	cat "$RUN/jobs/e2e.out"
	e2e=$(rc e2e)
fi
[ "${WOLLY_MUTATE:-0}" = 1 ] || echo "mutations: off (WOLLY_MUTATE=1 runs them)"
echo "gate: unit-rc=$unit contracts-rc=$contracts mutations=$(( nm + ns )) caught=$caught missed=$missed broken=$broken build-rc=$build e2e-rc=$e2e"
[ "$unit" -eq 0 ] && [ $contracts -eq 0 ] && [ $missed -eq 0 ] && [ $broken -eq 0 ] && [ "$build" -eq 0 ] && [ "$e2e" -eq 0 ]
