PROJ_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Configuration of extension
EXT_NAME=cnshift
EXT_CONFIG=${PROJ_DIR}extension_config.cmake

# Include the Makefile from extension-ci-tools
include extension-ci-tools/makefiles/duckdb_extension.Makefile

# Sources live under ext/src (not the template default src/).
format-check:
	python3 duckdb/scripts/format.py --all --check --directories ext/src src test
format:
	python3 duckdb/scripts/format.py --all --fix --noconfirm --directories ext/src src test
format-fix:
	python3 duckdb/scripts/format.py --all --fix --noconfirm --directories ext/src src test
