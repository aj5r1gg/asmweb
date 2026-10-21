PROJECT := asmweb

NASM := nasm
LD := ld
READELF := readelf
OBJDUMP := objdump
NM := nm
SIZE := size

SRC_DIR := src
INC_DIR := include
BUILD_DIR := build

NASMFLAGS := -f elf64 -Wall -Werror -Wno-error=reloc-rel-dword -I$(INC_DIR)/
# Explicit ELF process hardening.
#
# AsmWeb does not execute code from the process stack. Every production and
# qualification binary linked through this Makefile SHALL carry an explicit
# non-executable GNU_STACK policy.
LDFLAGS := -z noexecstack

SOURCES := $(shell find $(SRC_DIR) -type f -name '*.asm' | sort)
OBJECTS := $(patsubst $(SRC_DIR)/%.asm,$(BUILD_DIR)/%.o,$(SOURCES))
TARGET := $(BUILD_DIR)/$(PROJECT)

.PHONY: all clean inspect toolchain qualify-process-entry qualify-entropy qualify-cpu qualify-time qualify-memory qualify-mapping-capacity qualify-registry qualify-rrr qualify-runtime-rules qualify-runtime-rules-spec qualify-process-runtime qualify-arithmetic qualify-memory-ceiling qualify-elf-hardening qualify-production-registry

all: $(TARGET)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.asm
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(TARGET): $(OBJECTS)
	@if [ -z "$(OBJECTS)" ]; then \
		echo "No assembly objects exist yet; nothing to link."; \
		exit 1; \
	fi
	$(LD) $(LDFLAGS) -o $@ $(OBJECTS)

inspect: $(TARGET)
	$(READELF) -h $(TARGET)
	$(READELF) -lW $(TARGET)
	$(READELF) -SW $(TARGET)
	$(NM) -n $(TARGET)
	$(SIZE) $(TARGET)
	$(OBJDUMP) -d -Mintel $(TARGET)

toolchain:
	@printf 'NASM: '
	@$(NASM) -v
	@printf 'LD: '
	@$(LD) --version | head -n 1
	@printf 'READELF: '
	@$(READELF) --version | head -n 1
	@printf 'OBJDUMP: '
	@$(OBJDUMP) --version | head -n 1

clean:
	rm -rf $(BUILD_DIR)/*
	touch $(BUILD_DIR)/.gitkeep


# ---------------------------------------------------------------------------
# M0 qualification — controlled Linux process-entry parser
# ---------------------------------------------------------------------------

PROCESS_ENTRY_QUAL_SOURCE := tests/qualification/process_entry.asm
PROCESS_ENTRY_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/process_entry.o
PROCESS_ENTRY_QUAL_TARGET := $(BUILD_DIR)/qualification/process-entry

$(PROCESS_ENTRY_QUAL_OBJECT): $(PROCESS_ENTRY_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(PROCESS_ENTRY_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/platform/process_entry.o \
		$(PROCESS_ENTRY_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/platform/process_entry.o \
		$(PROCESS_ENTRY_QUAL_OBJECT)

qualify-process-entry: $(PROCESS_ENTRY_QUAL_TARGET)
	$(PROCESS_ENTRY_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — entropy bootstrap
# ---------------------------------------------------------------------------

ENTROPY_QUAL_SOURCE := tests/qualification/entropy.asm
ENTROPY_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/entropy.o
ENTROPY_QUAL_TARGET := $(BUILD_DIR)/qualification/entropy

$(ENTROPY_QUAL_OBJECT): $(ENTROPY_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(ENTROPY_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/entropy.o \
		$(ENTROPY_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/entropy.o \
		$(ENTROPY_QUAL_OBJECT)

qualify-entropy: $(ENTROPY_QUAL_TARGET)
	$(ENTROPY_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — CPU feature discovery
# ---------------------------------------------------------------------------

CPU_QUAL_SOURCE := tests/qualification/cpu.asm
CPU_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/cpu.o
CPU_QUAL_TARGET := $(BUILD_DIR)/qualification/cpu

$(CPU_QUAL_OBJECT): $(CPU_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(CPU_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/platform/cpu.o \
		$(CPU_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/platform/cpu.o \
		$(CPU_QUAL_OBJECT)

qualify-cpu: $(CPU_QUAL_TARGET)
	$(CPU_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — monotonic time
# ---------------------------------------------------------------------------

TIME_QUAL_SOURCE := tests/qualification/time.asm
TIME_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/time.o
TIME_QUAL_TARGET := $(BUILD_DIR)/qualification/time

$(TIME_QUAL_OBJECT): $(TIME_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(TIME_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/platform/time.o \
		$(TIME_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/platform/time.o \
		$(TIME_QUAL_OBJECT)

qualify-time: $(TIME_QUAL_TARGET)
	$(TIME_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — controlled memory mapping
# ---------------------------------------------------------------------------

MEMORY_QUAL_SOURCE := tests/qualification/memory.asm
MEMORY_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/memory.o
MEMORY_QUAL_TARGET := $(BUILD_DIR)/qualification/memory

$(MEMORY_QUAL_OBJECT): $(MEMORY_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(MEMORY_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/platform/memory.o \
		$(MEMORY_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/platform/memory.o \
		$(MEMORY_QUAL_OBJECT)

qualify-memory: $(MEMORY_QUAL_TARGET)
	$(MEMORY_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — bounded mapping capacity/accounting
# ---------------------------------------------------------------------------

MAPPING_CAPACITY_QUAL_SOURCE := tests/qualification/mapping_capacity.asm
MAPPING_CAPACITY_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/mapping_capacity.o
MAPPING_CAPACITY_QUAL_TARGET := $(BUILD_DIR)/qualification/mapping-capacity

$(MAPPING_CAPACITY_QUAL_OBJECT): $(MAPPING_CAPACITY_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(MAPPING_CAPACITY_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/platform/memory.o \
		$(BUILD_DIR)/runtime/mapping_capacity.o \
		$(MAPPING_CAPACITY_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/platform/memory.o \
		$(BUILD_DIR)/runtime/mapping_capacity.o \
		$(MAPPING_CAPACITY_QUAL_OBJECT)

qualify-mapping-capacity: $(MAPPING_CAPACITY_QUAL_TARGET)
	$(MAPPING_CAPACITY_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — fixed-class direct memory arithmetic
# ---------------------------------------------------------------------------

MEMORY_CEILING_QUAL_SOURCE := tests/qualification/memory_ceiling.asm
MEMORY_CEILING_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/memory_ceiling.o
MEMORY_CEILING_QUAL_TARGET := $(BUILD_DIR)/qualification/memory-ceiling

$(MEMORY_CEILING_QUAL_OBJECT): $(MEMORY_CEILING_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(MEMORY_CEILING_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(MEMORY_CEILING_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(MEMORY_CEILING_QUAL_OBJECT)

qualify-memory-ceiling: $(MEMORY_CEILING_QUAL_TARGET)
	$(MEMORY_CEILING_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — checked unsigned capacity arithmetic
# ---------------------------------------------------------------------------

ARITHMETIC_QUAL_SOURCE := tests/qualification/arithmetic.asm
ARITHMETIC_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/arithmetic.o
ARITHMETIC_QUAL_TARGET := $(BUILD_DIR)/qualification/arithmetic

$(ARITHMETIC_QUAL_OBJECT): $(ARITHMETIC_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(ARITHMETIC_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(ARITHMETIC_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(ARITHMETIC_QUAL_OBJECT)

qualify-arithmetic: $(ARITHMETIC_QUAL_TARGET)
	$(ARITHMETIC_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — canonical production OLR / MOT / RCT projection
# ---------------------------------------------------------------------------

PRODUCTION_REGISTRY_QUAL_SOURCE := tests/qualification/production_registry.asm
PRODUCTION_REGISTRY_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/production_registry.o
PRODUCTION_REGISTRY_QUAL_TARGET := $(BUILD_DIR)/qualification/production-registry

$(PRODUCTION_REGISTRY_QUAL_OBJECT): $(PRODUCTION_REGISTRY_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(PRODUCTION_REGISTRY_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(BUILD_DIR)/runtime/production_registry.o \
		$(PRODUCTION_REGISTRY_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(BUILD_DIR)/runtime/production_registry.o \
		$(PRODUCTION_REGISTRY_QUAL_OBJECT)

.PHONY: qualify-production-registry
qualify-production-registry: $(PRODUCTION_REGISTRY_QUAL_TARGET)
	$(PRODUCTION_REGISTRY_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — process runtime state and memory epochs
# ---------------------------------------------------------------------------

PROCESS_RUNTIME_QUAL_SOURCE := tests/qualification/process_runtime.asm
PROCESS_RUNTIME_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/process_runtime.o
PROCESS_RUNTIME_QUAL_TARGET := $(BUILD_DIR)/qualification/process-runtime

$(PROCESS_RUNTIME_QUAL_OBJECT): $(PROCESS_RUNTIME_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(PROCESS_RUNTIME_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(BUILD_DIR)/runtime/startup_memory.o \
		$(BUILD_DIR)/runtime/process_runtime.o \
		$(PROCESS_RUNTIME_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(BUILD_DIR)/runtime/startup_memory.o \
		$(BUILD_DIR)/runtime/process_runtime.o \
		$(PROCESS_RUNTIME_QUAL_OBJECT)

qualify-process-runtime: $(PROCESS_RUNTIME_QUAL_TARGET)
	$(PROCESS_RUNTIME_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — canonical Runtime & Memory v0.3 Runtime Rule Registry
# ---------------------------------------------------------------------------

RUNTIME_RULES_QUAL_SOURCE := tests/qualification/runtime_rules.asm
RUNTIME_RULES_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/runtime_rules.o
RUNTIME_RULES_QUAL_TARGET := $(BUILD_DIR)/qualification/runtime-rules

$(RUNTIME_RULES_QUAL_OBJECT): $(RUNTIME_RULES_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(RUNTIME_RULES_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(BUILD_DIR)/runtime/runtime_rules.o \
		$(RUNTIME_RULES_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(BUILD_DIR)/runtime/runtime_rules.o \
		$(RUNTIME_RULES_QUAL_OBJECT)

qualify-runtime-rules: $(RUNTIME_RULES_QUAL_TARGET)
	$(RUNTIME_RULES_QUAL_TARGET)

qualify-runtime-rules-spec:
	python3 tests/qualification/runtime_rules_spec.py


# ---------------------------------------------------------------------------
# M0 qualification — Runtime Rule Registry identity/status foundation
# ---------------------------------------------------------------------------

RRR_QUAL_SOURCE := tests/qualification/rrr.asm
RRR_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/rrr.o
RRR_QUAL_TARGET := $(BUILD_DIR)/qualification/rrr

$(RRR_QUAL_OBJECT): $(RRR_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(RRR_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(RRR_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(RRR_QUAL_OBJECT)

qualify-rrr: $(RRR_QUAL_TARGET)
	$(RRR_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — runtime registry consistency foundation
# ---------------------------------------------------------------------------

REGISTRY_QUAL_SOURCE := tests/qualification/registry.asm
REGISTRY_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/registry.o
REGISTRY_QUAL_TARGET := $(BUILD_DIR)/qualification/registry

$(REGISTRY_QUAL_OBJECT): $(REGISTRY_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(REGISTRY_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(REGISTRY_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(REGISTRY_QUAL_OBJECT)

qualify-registry: $(REGISTRY_QUAL_TARGET)
	$(REGISTRY_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — startup peak direct-memory accounting
# ---------------------------------------------------------------------------

STARTUP_MEMORY_QUAL_SOURCE := tests/qualification/startup_memory.asm
STARTUP_MEMORY_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/startup_memory.o
STARTUP_MEMORY_QUAL_TARGET := $(BUILD_DIR)/qualification/startup-memory

$(STARTUP_MEMORY_QUAL_OBJECT): $(STARTUP_MEMORY_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(STARTUP_MEMORY_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/startup_memory.o \
		$(STARTUP_MEMORY_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/startup_memory.o \
		$(STARTUP_MEMORY_QUAL_OBJECT)

.PHONY: qualify-startup-memory
qualify-startup-memory: $(STARTUP_MEMORY_QUAL_TARGET)
	$(STARTUP_MEMORY_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — guarded stack provisioning foundation
# ---------------------------------------------------------------------------

STACK_QUAL_SOURCE := tests/qualification/stack.asm
STACK_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/stack.o
STACK_QUAL_TARGET := $(BUILD_DIR)/qualification/stack

$(STACK_QUAL_OBJECT): $(STACK_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(STACK_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/platform/memory.o \
		$(BUILD_DIR)/runtime/mapping_capacity.o \
		$(BUILD_DIR)/runtime/stack.o \
		$(STACK_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/platform/memory.o \
		$(BUILD_DIR)/runtime/mapping_capacity.o \
		$(BUILD_DIR)/runtime/stack.o \
		$(STACK_QUAL_OBJECT)

.PHONY: qualify-stack
qualify-stack: $(STACK_QUAL_TARGET)
	$(STACK_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — typed bounded-pool foundation
# ---------------------------------------------------------------------------

POOL_QUAL_SOURCE := tests/qualification/pool.asm
POOL_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/pool.o
POOL_QUAL_TARGET := $(BUILD_DIR)/qualification/pool

$(POOL_QUAL_OBJECT): $(POOL_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(POOL_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/pool.o \
		$(POOL_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/pool.o \
		$(POOL_QUAL_OBJECT)

.PHONY: qualify-pool
qualify-pool: $(POOL_QUAL_TARGET)
	$(POOL_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — telemetry foundations
# ---------------------------------------------------------------------------

TELEMETRY_QUAL_SOURCE := tests/qualification/telemetry.asm
TELEMETRY_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/telemetry.o
TELEMETRY_QUAL_TARGET := $(BUILD_DIR)/qualification/telemetry

$(TELEMETRY_QUAL_OBJECT): $(TELEMETRY_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(TELEMETRY_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/platform/memory.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(BUILD_DIR)/runtime/process_runtime.o \
		$(BUILD_DIR)/runtime/startup_memory.o \
		$(BUILD_DIR)/runtime/mapping_capacity.o \
		$(BUILD_DIR)/runtime/pool.o \
		$(BUILD_DIR)/runtime/quiescence.o \
		$(BUILD_DIR)/runtime/telemetry.o \
		$(TELEMETRY_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/platform/memory.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(BUILD_DIR)/runtime/process_runtime.o \
		$(BUILD_DIR)/runtime/startup_memory.o \
		$(BUILD_DIR)/runtime/mapping_capacity.o \
		$(BUILD_DIR)/runtime/pool.o \
		$(BUILD_DIR)/runtime/quiescence.o \
		$(BUILD_DIR)/runtime/telemetry.o \
		$(TELEMETRY_QUAL_OBJECT)

.PHONY: qualify-telemetry
qualify-telemetry: $(TELEMETRY_QUAL_TARGET)
	$(TELEMETRY_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — runtime READY invariant composition
# ---------------------------------------------------------------------------

RUNTIME_INVARIANT_QUAL_SOURCE := tests/qualification/runtime_invariant.asm
RUNTIME_INVARIANT_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/runtime_invariant.o
RUNTIME_INVARIANT_QUAL_TARGET := $(BUILD_DIR)/qualification/runtime-invariant

$(RUNTIME_INVARIANT_QUAL_OBJECT): $(RUNTIME_INVARIANT_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(RUNTIME_INVARIANT_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(BUILD_DIR)/runtime/process_runtime.o \
		$(BUILD_DIR)/runtime/startup_memory.o \
		$(BUILD_DIR)/runtime/config_dependency.o \
		$(BUILD_DIR)/runtime/runtime_invariant.o \
		$(RUNTIME_INVARIANT_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(BUILD_DIR)/runtime/process_runtime.o \
		$(BUILD_DIR)/runtime/startup_memory.o \
		$(BUILD_DIR)/runtime/config_dependency.o \
		$(BUILD_DIR)/runtime/runtime_invariant.o \
		$(RUNTIME_INVARIANT_QUAL_OBJECT)

.PHONY: qualify-runtime-invariant
qualify-runtime-invariant: $(RUNTIME_INVARIANT_QUAL_TARGET)
	$(RUNTIME_INVARIANT_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — configuration capacity dependencies
# ---------------------------------------------------------------------------

CONFIG_DEPENDENCY_QUAL_SOURCE := tests/qualification/config_dependency.asm
CONFIG_DEPENDENCY_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/config_dependency.o
CONFIG_DEPENDENCY_QUAL_TARGET := $(BUILD_DIR)/qualification/config-dependency

$(CONFIG_DEPENDENCY_QUAL_OBJECT): $(CONFIG_DEPENDENCY_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(CONFIG_DEPENDENCY_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/config_dependency.o \
		$(CONFIG_DEPENDENCY_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/config_dependency.o \
		$(CONFIG_DEPENDENCY_QUAL_OBJECT)

.PHONY: qualify-config-dependency
qualify-config-dependency: $(CONFIG_DEPENDENCY_QUAL_TARGET)
	$(CONFIG_DEPENDENCY_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — quiescence machinery
# ---------------------------------------------------------------------------

QUIESCENCE_QUAL_SOURCE := tests/qualification/quiescence.asm
QUIESCENCE_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/quiescence.o
QUIESCENCE_QUAL_TARGET := $(BUILD_DIR)/qualification/quiescence

$(QUIESCENCE_QUAL_OBJECT): $(QUIESCENCE_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(QUIESCENCE_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/pool.o \
		$(BUILD_DIR)/runtime/quiescence.o \
		$(BUILD_DIR)/runtime/startup_memory.o \
		$(QUIESCENCE_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/pool.o \
		$(BUILD_DIR)/runtime/quiescence.o \
		$(BUILD_DIR)/runtime/startup_memory.o \
		$(QUIESCENCE_QUAL_OBJECT)

.PHONY: qualify-quiescence
qualify-quiescence: $(QUIESCENCE_QUAL_TARGET)
	$(QUIESCENCE_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — ownership / publication semantics
# ---------------------------------------------------------------------------

OWNERSHIP_PUBLICATION_QUAL_SOURCE := tests/qualification/ownership_publication.asm
OWNERSHIP_PUBLICATION_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/ownership_publication.o
OWNERSHIP_PUBLICATION_QUAL_TARGET := $(BUILD_DIR)/qualification/ownership-publication

$(OWNERSHIP_PUBLICATION_QUAL_OBJECT): $(OWNERSHIP_PUBLICATION_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(OWNERSHIP_PUBLICATION_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/pool.o \
		$(OWNERSHIP_PUBLICATION_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/pool.o \
		$(OWNERSHIP_PUBLICATION_QUAL_OBJECT)

.PHONY: qualify-ownership-publication
qualify-ownership-publication: $(OWNERSHIP_PUBLICATION_QUAL_TARGET)
	$(OWNERSHIP_PUBLICATION_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — controlled qualification fault hooks
# ---------------------------------------------------------------------------

FAULT_HOOK_COMMON_SOURCE := tests/qualification/fault_hook.asm
FAULT_HOOK_COMMON_OBJECT := $(BUILD_DIR)/tests/qualification/fault_hook.o

FAULT_HOOK_QUAL_SOURCE := tests/qualification/fault_hook_qualification.asm
FAULT_HOOK_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/fault_hook_qualification.o
FAULT_HOOK_QUAL_TARGET := $(BUILD_DIR)/qualification/fault-hook

$(FAULT_HOOK_COMMON_OBJECT): $(FAULT_HOOK_COMMON_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -Itests/qualification/ -o $@ $<

$(FAULT_HOOK_QUAL_OBJECT): $(FAULT_HOOK_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -Itests/qualification/ -o $@ $<

$(FAULT_HOOK_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/pool.o \
		$(FAULT_HOOK_COMMON_OBJECT) \
		$(FAULT_HOOK_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/pool.o \
		$(FAULT_HOOK_COMMON_OBJECT) \
		$(FAULT_HOOK_QUAL_OBJECT)

.PHONY: qualify-fault-hook
qualify-fault-hook: $(FAULT_HOOK_QUAL_TARGET)
	$(FAULT_HOOK_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — transactional multi-resource acquisition rollback
# ---------------------------------------------------------------------------

ACQUISITION_ROLLBACK_QUAL_SOURCE := tests/qualification/acquisition_rollback.asm
ACQUISITION_ROLLBACK_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/acquisition_rollback.o
ACQUISITION_ROLLBACK_QUAL_TARGET := $(BUILD_DIR)/qualification/acquisition-rollback

$(ACQUISITION_ROLLBACK_QUAL_OBJECT): $(ACQUISITION_ROLLBACK_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(ACQUISITION_ROLLBACK_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/pool.o \
		$(ACQUISITION_ROLLBACK_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/pool.o \
		$(ACQUISITION_ROLLBACK_QUAL_OBJECT)

.PHONY: qualify-acquisition-rollback
qualify-acquisition-rollback: $(ACQUISITION_ROLLBACK_QUAL_TARGET)
	$(ACQUISITION_ROLLBACK_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — stale-reference identity candidate
# ---------------------------------------------------------------------------

STALE_CANDIDATE_QUAL_SOURCE := tests/qualification/stale_candidate.asm
STALE_CANDIDATE_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/stale_candidate.o
STALE_CANDIDATE_QUAL_TARGET := $(BUILD_DIR)/qualification/stale-candidate

$(STALE_CANDIDATE_QUAL_OBJECT): $(STALE_CANDIDATE_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(STALE_CANDIDATE_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/pool.o \
		$(BUILD_DIR)/runtime/stale_candidate.o \
		$(STALE_CANDIDATE_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/pool.o \
		$(BUILD_DIR)/runtime/stale_candidate.o \
		$(STALE_CANDIDATE_QUAL_OBJECT)

.PHONY: qualify-stale-candidate
qualify-stale-candidate: $(STALE_CANDIDATE_QUAL_TARGET)
	$(STALE_CANDIDATE_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — ELF/process hardening
# ---------------------------------------------------------------------------

qualify-elf-hardening: $(TARGET)
	./tests/qualification/elf_hardening.sh $(TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — formal qualification infrastructure foundation
# ---------------------------------------------------------------------------

.PHONY: qualify-qualification-foundation
qualify-qualification-foundation:
	python3 tests/qualification/qualification_foundation.py
	python3 tests/qualification/verification_class_contract.py


.PHONY: qualification-m0-foundation-evidence
qualification-m0-foundation-evidence: $(TARGET)
	python3 qualification/tools/qualification_foundation.py \
		emit-m0-foundation

.PHONY: qualify-qrr-slice
qualify-qrr-slice:
	python3 tests/qualification/qrr_slice.py

build-qrr:
	python3 qualification/tools/qrr_authority.py build

qualify-qrr-authority:
	python3 tests/qualification/qrr_authority.py

# ---------------------------------------------------------------------------
# M0 qualification — frozen Requirements source authority
# ---------------------------------------------------------------------------

.PHONY: qualify-requirements-authority
qualify-requirements-authority:
	python3 qualification/tools/requirements_authority.py
	python3 tests/qualification/requirements_authority.py

# ---------------------------------------------------------------------------
# M0 qualification — draft operational Requirements Registry
# ---------------------------------------------------------------------------

.PHONY: qualify-requirements-registry
qualify-requirements-registry:
	python3 qualification/tools/requirements_registry.py
	python3 tests/qualification/requirements_registry.py

# ---------------------------------------------------------------------------
# M0 qualification — draft Requirements milestone ownership register
# ---------------------------------------------------------------------------

.PHONY: qualify-requirements-ownership
qualify-requirements-ownership:
	python3 qualification/tools/requirements_ownership.py
	python3 tests/qualification/requirements_ownership.py

# ---------------------------------------------------------------------------
# M0 qualification — pending ownership proposals
# ---------------------------------------------------------------------------

.PHONY: qualify-m0-ownership-proposals
qualify-m0-ownership-proposals:
	python3 qualification/tools/m0_ownership_proposals.py
	python3 tests/qualification/m0_ownership_proposals.py

# ---------------------------------------------------------------------------
# M0 qualification — non-effective ownership approval simulation
# ---------------------------------------------------------------------------

.PHONY: qualify-m0-ownership-dry-run
qualify-m0-ownership-dry-run:
	python3 qualification/tools/m0_ownership_dry_run.py --requirement REQ-M0-001
	python3 tests/qualification/m0_ownership_dry_run.py

# ---------------------------------------------------------------------------
# M0 qualification — unadopted ownership decision contract
# ---------------------------------------------------------------------------

.PHONY: qualify-ownership-decision-contract
qualify-ownership-decision-contract:
	python3 qualification/tools/ownership_decision_contract.py
	python3 tests/qualification/ownership_decision_contract.py

# M0 READY-state invariant implementation register
.PHONY: qualify-runtime-invariant-register
qualify-runtime-invariant-register:
	python3 qualification/tools/runtime_invariant_register.py
	python3 tests/qualification/runtime_invariant_register.py

# M0 bounded MOT-shaped limit calculation engine
.PHONY: qualify-effective-limit-engine
qualify-effective-limit-engine:
	python3 tests/qualification/effective_limit_engine.py

# M0 assembly-compatible MOT maximum-memory derivation
.PHONY: qualify-mot-ceiling-integration
qualify-mot-ceiling-integration:
	python3 tests/qualification/mot_ceiling_integration.py

# M0 production registry derived MOT projection
.PHONY: qualify-production-limit-manifest
qualify-production-limit-manifest:
	python3 qualification/tools/production_limit_manifest.py
	python3 tests/qualification/production_limit_manifest.py

# ---------------------------------------------------------------------------
# NASM generated dependency files
#
# Every assembled object produces a matching .d file using NASM's own
# transitive include discovery.
#
# Missing dependency files are permitted during the first build.
# Existing dependency files are included for incremental rebuilds.
#
# Production and qualification objects use the same mechanism.
# ---------------------------------------------------------------------------

-include $(wildcard $(BUILD_DIR)/*.d $(BUILD_DIR)/*/*.d $(BUILD_DIR)/*/*/*.d)

# ---------------------------------------------------------------------------
# M1.5.2-D4 — HTTP descriptor lifecycle (qualification-only network stubs)
# ---------------------------------------------------------------------------

HTTP_FD_QUAL_SOURCE := tests/qualification/http_descriptor_lifecycle.asm
HTTP_FD_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/http_descriptor_lifecycle.o
HTTP_FD_QUAL_TARGET := $(BUILD_DIR)/qualification/http-descriptor-lifecycle

$(HTTP_FD_QUAL_OBJECT): $(HTTP_FD_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(HTTP_FD_QUAL_TARGET): \
		$(BUILD_DIR)/http/first_response.o \
		$(BUILD_DIR)/platform/time.o \
		$(BUILD_DIR)/platform/deadline.o \
		$(HTTP_FD_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ $^

.PHONY: qualify-http-descriptor-lifecycle
qualify-http-descriptor-lifecycle: $(HTTP_FD_QUAL_TARGET)
	$(HTTP_FD_QUAL_TARGET)

# Qualification-only mutation sensitivity.
.PHONY: qualify-http-descriptor-mutations
qualify-http-descriptor-mutations: $(HTTP_FD_QUAL_TARGET)
	python3 tests/qualification/http_descriptor_mutations.py

# Track NASM include-file dependencies for the HTTP lifecycle harness.
-include $(HTTP_FD_QUAL_OBJECT:.o=.d)

# ---------------------------------------------------------------------------
# M1 — Absolute HTTP request-acquisition deadline qualification
# ---------------------------------------------------------------------------

.PHONY: qualify-http-acquisition-deadline
qualify-http-acquisition-deadline: $(TARGET)
	timeout 30s python3 tests/integration/http_acquisition_deadline.py

.PHONY: qualify-http-deadline-mutations
qualify-http-deadline-mutations: $(TARGET)
	timeout 60s python3 tests/qualification/http_deadline_mutations.py

# Run sequentially: both live tests use the same local HTTP port.
.PHONY: qualify-http-deadline-security
qualify-http-deadline-security:
	$(MAKE) -j1 qualify-time qualify-deadline \
		qualify-http-descriptor-lifecycle \
		qualify-http-descriptor-mutations \
		qualify-http-acquisition-deadline \
		qualify-http-deadline-mutations


# ---------------------------------------------------------------------------
# CP-LEGACY-M1-5 — Historical reconciliation engineering verification
# ---------------------------------------------------------------------------

.PHONY: qualify-checkpoint-reconciliation
qualify-checkpoint-reconciliation:
	python3 qualification/tools/checkpoint_reconciliation.py

.PHONY: qualify-checkpoint-reconciliation-adversarial
qualify-checkpoint-reconciliation-adversarial: qualify-checkpoint-reconciliation
	python3 tests/qualification/checkpoint_reconciliation.py

# ---------------------------------------------------------------------------
# M0-DIAG-001 — bounded first-failure diagnostics (engineering-only)
# ---------------------------------------------------------------------------

DIAGNOSTIC_QUAL_SOURCE := tests/qualification/diagnostic.asm
DIAGNOSTIC_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/diagnostic.o
DIAGNOSTIC_QUAL_TARGET := $(BUILD_DIR)/qualification/diagnostic

$(DIAGNOSTIC_QUAL_OBJECT): $(DIAGNOSTIC_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(DIAGNOSTIC_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/diagnostic.o \
		$(DIAGNOSTIC_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/diagnostic.o \
		$(DIAGNOSTIC_QUAL_OBJECT)

.PHONY: qualify-diagnostic
qualify-diagnostic: $(DIAGNOSTIC_QUAL_TARGET)
	$(DIAGNOSTIC_QUAL_TARGET)

-include $(DIAGNOSTIC_QUAL_OBJECT:.o=.d)

.PHONY: qualify-diagnostic-adversarial
qualify-diagnostic-adversarial: qualify-diagnostic
	python3 tests/qualification/diagnostic_mutations.py

# ---------------------------------------------------------------------------
# M0-DIAG-001 — permanent independent boundary and ABI harness
# ---------------------------------------------------------------------------

DIAGNOSTIC_BOUNDARY_SOURCE := tests/qualification/diagnostic_boundary.asm
DIAGNOSTIC_BOUNDARY_OBJECT := $(BUILD_DIR)/tests/qualification/diagnostic_boundary.o
DIAGNOSTIC_BOUNDARY_TARGET := $(BUILD_DIR)/qualification/diagnostic-boundary

$(DIAGNOSTIC_BOUNDARY_OBJECT): $(DIAGNOSTIC_BOUNDARY_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(DIAGNOSTIC_BOUNDARY_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/diagnostic.o \
		$(DIAGNOSTIC_BOUNDARY_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/diagnostic.o \
		$(DIAGNOSTIC_BOUNDARY_OBJECT)

.PHONY: qualify-diagnostic-boundary
qualify-diagnostic-boundary: $(DIAGNOSTIC_BOUNDARY_TARGET)
	$(DIAGNOSTIC_BOUNDARY_TARGET)

-include $(DIAGNOSTIC_BOUNDARY_OBJECT:.o=.d)

# ---------------------------------------------------------------------------
# M0-DIAG-002 — actual READY-validator diagnostic adapter
# ---------------------------------------------------------------------------

READY_DIAGNOSTIC_QUAL_SOURCE := tests/qualification/ready_diagnostic.asm
READY_DIAGNOSTIC_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/ready_diagnostic.o
READY_DIAGNOSTIC_QUAL_TARGET := $(BUILD_DIR)/qualification/ready-diagnostic

$(READY_DIAGNOSTIC_QUAL_OBJECT): $(READY_DIAGNOSTIC_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(READY_DIAGNOSTIC_QUAL_TARGET): \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/arithmetic.o \
		$(BUILD_DIR)/runtime/memory_ceiling.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(BUILD_DIR)/runtime/process_runtime.o \
		$(BUILD_DIR)/runtime/startup_memory.o \
		$(BUILD_DIR)/runtime/config_dependency.o \
		$(BUILD_DIR)/runtime/runtime_invariant.o \
		$(BUILD_DIR)/runtime/diagnostic.o \
		$(BUILD_DIR)/runtime/ready_diagnostic.o \
		$(READY_DIAGNOSTIC_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ $^

.PHONY: qualify-ready-diagnostic
qualify-ready-diagnostic: $(READY_DIAGNOSTIC_QUAL_TARGET)
	$(READY_DIAGNOSTIC_QUAL_TARGET)

-include $(READY_DIAGNOSTIC_QUAL_OBJECT:.o=.d)

# M0-DIAG-002 — controlled full-bootstrap failure injection.
.PHONY: qualify-ready-bootstrap-injection
qualify-ready-bootstrap-injection: all
	python3 tests/qualification/ready_bootstrap_injection.py

# M0-DIAG-003 — all READY classifications through the real adapter.
.PHONY: qualify-ready-diagnostic-matrix
qualify-ready-diagnostic-matrix: all
	python3 tests/qualification/ready_diagnostic_matrix.py

# ---------------------------------------------------------------------------
# M1 — UDP Network I/O Loopback Verification
# ---------------------------------------------------------------------------

UDP_LOOPBACK_SOURCE := tests/qualification/udp_loopback.asm
UDP_LOOPBACK_OBJECT := $(BUILD_DIR)/tests/qualification/udp_loopback.o
UDP_LOOPBACK_TARGET := $(BUILD_DIR)/qualification/udp-loopback

$(UDP_LOOPBACK_OBJECT): $(UDP_LOOPBACK_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(UDP_LOOPBACK_TARGET): $(UDP_LOOPBACK_OBJECT) $(BUILD_DIR)/linux/network.o
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ $^

.PHONY: qualify-udp-loopback
qualify-udp-loopback: $(UDP_LOOPBACK_TARGET)
	timeout 5s $(UDP_LOOPBACK_TARGET)

-include $(UDP_LOOPBACK_OBJECT:.o=.d)

# ---------------------------------------------------------------------------
# M1 — TCP accept4 Network I/O Verification
# ---------------------------------------------------------------------------

TCP_ACCEPT4_SOURCE := tests/qualification/tcp_accept4.asm
TCP_ACCEPT4_OBJECT := $(BUILD_DIR)/tests/qualification/tcp_accept4.o
TCP_ACCEPT4_TARGET := $(BUILD_DIR)/qualification/tcp-accept4

$(TCP_ACCEPT4_OBJECT): $(TCP_ACCEPT4_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(TCP_ACCEPT4_TARGET): $(TCP_ACCEPT4_OBJECT) $(BUILD_DIR)/linux/network.o
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ $^

.PHONY: qualify-tcp-accept4
qualify-tcp-accept4: $(TCP_ACCEPT4_TARGET)
	timeout 5s $(TCP_ACCEPT4_TARGET)

-include $(TCP_ACCEPT4_OBJECT:.o=.d)

# ---------------------------------------------------------------------------
# M1 — Network Error and Datagram Boundary Verification
# ---------------------------------------------------------------------------

NETWORK_ERRORS_SOURCE := tests/qualification/network_error_paths.asm
NETWORK_ERRORS_OBJECT := $(BUILD_DIR)/tests/qualification/network_error_paths.o
NETWORK_ERRORS_TARGET := $(BUILD_DIR)/qualification/network-error-paths

$(NETWORK_ERRORS_OBJECT): $(NETWORK_ERRORS_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(NETWORK_ERRORS_TARGET): $(NETWORK_ERRORS_OBJECT) $(BUILD_DIR)/linux/network.o
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ $^

.PHONY: qualify-network-error-paths
qualify-network-error-paths: $(NETWORK_ERRORS_TARGET)
	timeout 5s $(NETWORK_ERRORS_TARGET)

-include $(NETWORK_ERRORS_OBJECT:.o=.d)

# ---------------------------------------------------------------------------
# M1 — Fragmented Stream I/O Verification
# ---------------------------------------------------------------------------

STREAM_FRAGMENTS_SOURCE := tests/qualification/stream_fragments.asm
STREAM_FRAGMENTS_OBJECT := $(BUILD_DIR)/tests/qualification/stream_fragments.o
STREAM_FRAGMENTS_TARGET := $(BUILD_DIR)/qualification/stream-fragments

$(STREAM_FRAGMENTS_OBJECT): $(STREAM_FRAGMENTS_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(STREAM_FRAGMENTS_TARGET): $(STREAM_FRAGMENTS_OBJECT) $(BUILD_DIR)/linux/network.o
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ $^

.PHONY: qualify-stream-fragments
qualify-stream-fragments: $(STREAM_FRAGMENTS_TARGET)
	timeout 5s $(STREAM_FRAGMENTS_TARGET)

-include $(STREAM_FRAGMENTS_OBJECT:.o=.d)

# ---------------------------------------------------------------------------
# M1 — Nonblocking Stream Short-Write Verification
# ---------------------------------------------------------------------------

STREAM_SHORT_WRITE_SOURCE := tests/qualification/stream_short_write.asm
STREAM_SHORT_WRITE_OBJECT := $(BUILD_DIR)/tests/qualification/stream_short_write.o
STREAM_SHORT_WRITE_TARGET := $(BUILD_DIR)/qualification/stream-short-write

$(STREAM_SHORT_WRITE_OBJECT): $(STREAM_SHORT_WRITE_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(STREAM_SHORT_WRITE_TARGET): $(STREAM_SHORT_WRITE_OBJECT) $(BUILD_DIR)/linux/network.o
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ $^

.PHONY: qualify-stream-short-write
qualify-stream-short-write: $(STREAM_SHORT_WRITE_TARGET)
	timeout 5s $(STREAM_SHORT_WRITE_TARGET)

-include $(STREAM_SHORT_WRITE_OBJECT:.o=.d)

# ---------------------------------------------------------------------------
# M1 — Genuine Linux EINTR Verification
# ---------------------------------------------------------------------------

NETWORK_EINTR_SOURCE := tests/qualification/network_eintr.asm
NETWORK_EINTR_OBJECT := $(BUILD_DIR)/tests/qualification/network_eintr.o
NETWORK_EINTR_TARGET := $(BUILD_DIR)/qualification/network-eintr

$(NETWORK_EINTR_OBJECT): $(NETWORK_EINTR_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(NETWORK_EINTR_TARGET): $(NETWORK_EINTR_OBJECT) $(BUILD_DIR)/linux/network.o
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ $^

.PHONY: qualify-network-eintr
qualify-network-eintr: $(NETWORK_EINTR_TARGET)
	timeout 5s $(NETWORK_EINTR_TARGET)

-include $(NETWORK_EINTR_OBJECT:.o=.d)

# ---------------------------------------------------------------------------
# M1 qualification — absolute deadline arithmetic
# ---------------------------------------------------------------------------

DEADLINE_QUAL_SOURCE := tests/qualification/deadline.asm
DEADLINE_QUAL_OBJECT := $(BUILD_DIR)/tests/qualification/deadline.o
DEADLINE_QUAL_TARGET := $(BUILD_DIR)/qualification/deadline

$(DEADLINE_QUAL_OBJECT): $(DEADLINE_QUAL_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(DEADLINE_QUAL_TARGET): \
        $(BUILD_DIR)/platform/deadline.o \
        $(DEADLINE_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/platform/deadline.o \
		$(DEADLINE_QUAL_OBJECT)

.PHONY: qualify-deadline
qualify-deadline: $(DEADLINE_QUAL_TARGET)
	timeout 5s $(DEADLINE_QUAL_TARGET)

-include $(DEADLINE_QUAL_OBJECT:.o=.d)

# ---------------------------------------------------------------------------
# M1 — Real Batched UDP Datagram Qualification
# ---------------------------------------------------------------------------

UDP_BATCH_TRANSFER_SOURCE := tests/qualification/udp_batch_transfer.asm
UDP_BATCH_TRANSFER_OBJECT := $(BUILD_DIR)/tests/qualification/udp_batch_transfer.o
UDP_BATCH_TRANSFER_TARGET := $(BUILD_DIR)/qualification/udp-batch-transfer

$(UDP_BATCH_TRANSFER_OBJECT): $(UDP_BATCH_TRANSFER_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(UDP_BATCH_TRANSFER_TARGET): $(UDP_BATCH_TRANSFER_OBJECT) $(BUILD_DIR)/linux/network.o
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ $^

.PHONY: qualify-udp-batch-transfer
qualify-udp-batch-transfer: $(UDP_BATCH_TRANSFER_TARGET)
	timeout 5s $(UDP_BATCH_TRANSFER_TARGET)

-include $(UDP_BATCH_TRANSFER_OBJECT:.o=.d)

# ---------------------------------------------------------------------------
# M1 — UDP bounded batch argument qualification
# ---------------------------------------------------------------------------

UDP_BATCH_BOUNDS_SOURCE := tests/qualification/udp_batch_bounds.asm
UDP_BATCH_BOUNDS_OBJECT := $(BUILD_DIR)/tests/qualification/udp_batch_bounds.o
UDP_BATCH_BOUNDS_TARGET := $(BUILD_DIR)/qualification/udp-batch-bounds

$(UDP_BATCH_BOUNDS_OBJECT): $(UDP_BATCH_BOUNDS_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(UDP_BATCH_BOUNDS_TARGET): $(UDP_BATCH_BOUNDS_OBJECT) $(BUILD_DIR)/linux/network.o
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ $^

.PHONY: qualify-udp-batch-bounds
qualify-udp-batch-bounds: $(UDP_BATCH_BOUNDS_TARGET)
	timeout 5s $(UDP_BATCH_BOUNDS_TARGET)

-include $(UDP_BATCH_BOUNDS_OBJECT:.o=.d)

# ---------------------------------------------------------------------------
# M1 — UDP batch adversarial mutation qualification
# ---------------------------------------------------------------------------

.PHONY: qualify-udp-batch-mutations
qualify-udp-batch-mutations: \
    $(UDP_BATCH_BOUNDS_TARGET) \
    $(UDP_BATCH_TRANSFER_TARGET)
	python3 tests/qualification/udp_batch_mutations.py

# ---------------------------------------------------------------------------
# NET-005 — checked connected-UDP descriptor profile
# ---------------------------------------------------------------------------

UDP_CHECKED_SOURCE := tests/qualification/udp_checked_descriptors.asm
UDP_CHECKED_OBJECT := $(BUILD_DIR)/tests/qualification/udp_checked_descriptors.o
UDP_CHECKED_TARGET := $(BUILD_DIR)/qualification/udp-checked-descriptors

$(UDP_CHECKED_OBJECT): $(UDP_CHECKED_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(UDP_CHECKED_TARGET): \
		$(BUILD_DIR)/linux/network.o \
		$(UDP_CHECKED_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ $^

.PHONY: qualify-udp-checked-descriptors
qualify-udp-checked-descriptors: $(UDP_CHECKED_TARGET)
	timeout 5s $(UDP_CHECKED_TARGET)

-include $(UDP_CHECKED_OBJECT:.o=.d)

# ---------------------------------------------------------------------------
# NET-005 — checked connected-UDP real datagram transfer
# ---------------------------------------------------------------------------

UDP_CHECKED_TRANSFER_SOURCE := tests/qualification/udp_checked_transfer.asm
UDP_CHECKED_TRANSFER_OBJECT := $(BUILD_DIR)/tests/qualification/udp_checked_transfer.o
UDP_CHECKED_TRANSFER_TARGET := $(BUILD_DIR)/qualification/udp-checked-transfer

$(UDP_CHECKED_TRANSFER_OBJECT): $(UDP_CHECKED_TRANSFER_SOURCE)
	mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -MD $(@:.o=.d) -o $@ $<

$(UDP_CHECKED_TRANSFER_TARGET): $(BUILD_DIR)/linux/network.o $(UDP_CHECKED_TRANSFER_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ $^

.PHONY: qualify-udp-checked-transfer
qualify-udp-checked-transfer: $(UDP_CHECKED_TRANSFER_TARGET)
	timeout 5s $(UDP_CHECKED_TRANSFER_TARGET)

-include $(UDP_CHECKED_TRANSFER_OBJECT:.o=.d)

# NET-005 — adversarial checked-descriptor qualification
.PHONY: qualify-udp-checked-mutations
qualify-udp-checked-mutations: $(BUILD_DIR)/linux/network.o $(UDP_CHECKED_OBJECT)
	python3 tests/qualification/udp_checked_mutations.py

# M0: production Limit Register evidence qualification
.PHONY: qualify-m0-lr-evidence
qualify-m0-lr-evidence:
	python3 -B tests/qualification/m0_lr_evidence.py

# M0 governance invariant engineering trace
.PHONY: qualify-m0-governance-trace
qualify-m0-governance-trace:
	python3 -B tests/qualification/m0_governance_trace.py

# M0 fail-closed qualification preflight
.PHONY: qualify-m0-closure-gate
qualify-m0-closure-gate:
	python3 -B qualification/tools/m0_closure_gate.py audit
	python3 -B tests/qualification/m0_closure_gate.py

# REQ-M0-004: controlled requirement identity qualification
.PHONY: qualify-m0-requirement-identity
qualify-m0-requirement-identity:
	python3 -B qualification/tools/m0_ownership_review.py verify
	python3 -B tests/qualification/m0_requirement_identity.py

# REQ-M0-005: reproducible production binary identity
.PHONY: qualify-m0-binary-identity
qualify-m0-binary-identity: all
	python3 -B tests/qualification/m0_binary_identity.py
