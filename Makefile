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
LDFLAGS :=

SOURCES := $(shell find $(SRC_DIR) -type f -name '*.asm' | sort)
OBJECTS := $(patsubst $(SRC_DIR)/%.asm,$(BUILD_DIR)/%.o,$(SOURCES))
TARGET := $(BUILD_DIR)/$(PROJECT)

.PHONY: all clean inspect toolchain qualify-process-entry qualify-entropy qualify-cpu

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
