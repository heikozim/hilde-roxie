# ROXIE -- build and test inside the build container of Wolly.
#
#     make build   the programme _run/bin/roxie
#     make test    unit and contract tests, lint, build, end to end

WOLLY_ROOT ?= ../hilde-wolly

.PHONY: build test

build:
	WOLLY_ROOT=$(WOLLY_ROOT) bash scripts/in-build.sh

test:
	WOLLY_ROOT=$(WOLLY_ROOT) WOLLY_MUTATE=0 bash scripts/in-gate.sh
