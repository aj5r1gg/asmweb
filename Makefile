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

.PHONY: all clean inspect toolchain qualify-process-entry qualify-entropy qualify-cpu qualify-time qualify-memory qualify-mapping-capacity qualify-registry qualify-rrr qualify-runtime-rules qualify-runtime-rules-spec qualify-process-runtime qualify-arithmetic qualify-elf-hardening

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
		$(BUILD_DIR)/runtime/process_runtime.o \
		$(PROCESS_RUNTIME_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
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
		$(BUILD_DIR)/runtime/registry.o \
		$(BUILD_DIR)/runtime/runtime_rules.o \
		$(RUNTIME_RULES_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
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
		$(BUILD_DIR)/runtime/registry.o \
		$(RRR_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
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
		$(BUILD_DIR)/runtime/registry.o \
		$(REGISTRY_QUAL_OBJECT)
	mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -o $@ \
		$(BUILD_DIR)/linux/syscall.o \
		$(BUILD_DIR)/runtime/registry.o \
		$(REGISTRY_QUAL_OBJECT)

qualify-registry: $(REGISTRY_QUAL_TARGET)
	$(REGISTRY_QUAL_TARGET)


# ---------------------------------------------------------------------------
# M0 qualification — ELF/process hardening
# ---------------------------------------------------------------------------

qualify-elf-hardening: $(TARGET)
	./tests/qualification/elf_hardening.sh $(TARGET)
