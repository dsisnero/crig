CRYSTAL_CACHE_DIR ?= $(PWD)/.crystal-cache
install:
	shards install

update:
	shards update

format:
	crystal tool format --check src spec

lint:
	ameba src spec

test:
	CRYSTAL_CACHE_DIR=$(CRYSTAL_CACHE_DIR) crystal spec

clean:
	rm -rf .crystal-cache temp bin/examples

bench-parallel:
	CRYSTAL_CACHE_DIR=$(CRYSTAL_CACHE_DIR) crystal run --release -Dpreview_mt -Dexecution_context benchmarks/parallel_runtime_bench.cr

bench-mcp-dispatch:
	CRYSTAL_CACHE_DIR=$(CRYSTAL_CACHE_DIR) crystal run --release -Dpreview_mt -Dexecution_context benchmarks/mcp_dispatch_bench.cr

# Find all source files that examples might depend on
SRC_FILES := $(shell find src -name "*.cr")
EXAMPLE_SRC_FILES := $(wildcard examples/*.cr)
EXAMPLE_BINARIES := $(patsubst examples/%.cr,bin/examples/%,$(EXAMPLE_SRC_FILES))

# Helper function to check if an example needs rebuilding
define check_rebuild
	@mkdir -p bin/examples
	@if [ ! -f "bin/examples/$(1)" ] || [ "examples/$(1).cr" -nt "bin/examples/$(1)" ] || [ -n "$$(find src -name "*.cr" -newer "bin/examples/$(1)" 2>/dev/null | head -1)" ]; then \
		echo "Building $(1)..."; \
		crystal build "examples/$(1).cr" -o "bin/examples/$(1)" || exit 1; \
	else \
		echo "$(1) is up to date"; \
	fi
endef

# Individual example targets
$(foreach example,$(patsubst examples/%.cr,%,$(EXAMPLE_SRC_FILES)),\
	$(eval .PHONY: build-$(example))\
	$(eval build-$(example): ; $(call check_rebuild,$(example)))\
)

# Build all examples
build-examples:
	@for example in $(patsubst examples/%.cr,%,$(EXAMPLE_SRC_FILES)); do \
		$(MAKE) build-$$example; \
	done

.PHONY: install update format lint test clean build-examples bench-parallel bench-mcp-dispatch
