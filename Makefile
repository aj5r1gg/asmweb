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

.PHONY: all clean inspect toolchain

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
