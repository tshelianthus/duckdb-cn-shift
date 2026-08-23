PROJ_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Configuration of extension
EXT_NAME=cnshift
EXT_CONFIG=${PROJ_DIR}extension_config.cmake

# Include the Makefile from extension-ci-tools
include extension-ci-tools/makefiles/duckdb_extension.Makefile

# Sources live under ext/src (not only the template default src/).
# Same duckdb/scripts/format.py + clang-tidy entrypoints as community extensions.
format-check:
	python3 duckdb/scripts/format.py --all --check --directories ext/src src test
format:
	python3 duckdb/scripts/format.py --all --fix --noconfirm --directories ext/src src test
format-fix:
	python3 duckdb/scripts/format.py --all --fix --noconfirm --directories ext/src src test
tidy-check:
	mkdir -p ./build/tidy
	cmake $(GENERATOR) $(BUILD_FLAGS) $(EXT_DEBUG_FLAGS) -DDISABLE_UNITY=1 -DCLANG_TIDY=1 -S $(DUCKDB_SRCDIR) -B build/tidy
	cp duckdb/.clang-tidy build/tidy/.clang-tidy
	cd build/tidy && python3 ../../duckdb/scripts/run-clang-tidy.py '$(PROJ_DIR)(src|ext/src)/' -header-filter '$(PROJ_DIR)(src|ext/src)/' -quiet ${TIDY_THREAD_PARAMETER} ${TIDY_BINARY_PARAMETER} ${TIDY_PERFORM_CHECKS}
