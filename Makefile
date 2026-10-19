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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
	$(NASM) $(NASMFLAGS) -o $@ $<

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
