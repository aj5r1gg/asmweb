#!/usr/bin/env bash

set -u

TARGET=${1:-}

if [ -z "$TARGET" ]; then
    printf 'elf_hardening_error=missing_target\n'
    exit 1
fi

if [ ! -f "$TARGET" ]; then
    printf 'elf_hardening_error=target_not_found\n'
    exit 1
fi

fail()
{
    printf 'elf_hardening_failure=%s\n' "$1"
    exit 1
}

printf 'elf_hardening_target=%s\n' "$TARGET"

HEADER=$(readelf -hW "$TARGET") || fail readelf_header
PROGRAMS=$(readelf -lW "$TARGET") || fail readelf_program_headers
SECTIONS=$(readelf -SW "$TARGET") || fail readelf_sections
DYNAMIC=$(readelf -dW "$TARGET" 2>&1) || true
RELOCS=$(readelf -rW "$TARGET") || fail readelf_relocations

# ---------------------------------------------------------------------------
# ELF class / architecture / object type
# ---------------------------------------------------------------------------

printf '%s\n' "$HEADER" |
    grep -Eq 'Class:[[:space:]]+ELF64' ||
    fail not_elf64

printf '%s\n' "$HEADER" |
    grep -Eq 'Machine:[[:space:]]+Advanced Micro Devices X86-64' ||
    fail not_x86_64

printf '%s\n' "$HEADER" |
    grep -Eq 'Type:[[:space:]]+EXEC \(Executable file\)' ||
    fail unexpected_elf_type

# ---------------------------------------------------------------------------
# No runtime ELF loader / dynamic linking.
# ---------------------------------------------------------------------------

if printf '%s\n' "$PROGRAMS" |
    grep -qi 'INTERP'
then
    fail interpreter_present
fi

if ! printf '%s\n' "$DYNAMIC" |
    grep -q 'There is no dynamic section in this file'
then
    fail dynamic_section_present
fi

# ---------------------------------------------------------------------------
# No final linked relocations.
# ---------------------------------------------------------------------------

if ! printf '%s\n' "$RELOCS" |
    grep -q 'There are no relocations in this file'
then
    fail relocations_present
fi

# ---------------------------------------------------------------------------
# Explicit GNU_STACK policy.
#
# Require exactly one GNU_STACK program header.
# It must be readable/writable and MUST NOT be executable.
# ---------------------------------------------------------------------------

GNU_STACK_LINES=$(
    printf '%s\n' "$PROGRAMS" |
        grep -E '^[[:space:]]*GNU_STACK[[:space:]]' || true
)

GNU_STACK_COUNT=$(
    printf '%s\n' "$GNU_STACK_LINES" |
        awk 'NF { count++ } END { print count + 0 }'
)

if [ "$GNU_STACK_COUNT" -ne 1 ]; then
    fail gnu_stack_count
fi

GNU_STACK_LINE=$(
    printf '%s\n' "$GNU_STACK_LINES" |
        head -n 1
)

# readelf displays flags as separate R/W/E letters.
printf '%s\n' "$GNU_STACK_LINE" |
    grep -Eq '[[:space:]]RW[[:space:]]' ||
    fail gnu_stack_not_rw

printf '%s\n' "$GNU_STACK_LINE" |
    grep -Eq '[[:space:]]RWE[[:space:]]' &&
    fail executable_stack

# Collect every flag token between MemSiz and Align.
#
# readelf may display flags as:
#
#   RW
#
# or as separate tokens:
#
#   R E
#   RW E
#
# Do not assume the flags occupy exactly one field.
STACK_FLAGS=$(
    printf '%s\n' "$GNU_STACK_LINE" |
        awk '{
            flags = ""
            for (i = 7; i < NF; i++) {
                if ($i ~ /^[RWE]+$/)
                    flags = flags $i
            }
            print flags
        }'
)

case "$STACK_FLAGS" in
    *E*)
        fail executable_stack
        ;;
esac

case "$STACK_FLAGS" in
    *R*W*|*W*R*)
        ;;
    *)
        fail gnu_stack_not_rw
        ;;
esac

# ---------------------------------------------------------------------------
# LOAD segment policy.
#
# There must be at least one LOAD segment.
# No LOAD segment may simultaneously contain W and E.
# ---------------------------------------------------------------------------

LOAD_LINES=$(
    printf '%s\n' "$PROGRAMS" |
        grep -E '^[[:space:]]*LOAD[[:space:]]' || true
)

LOAD_COUNT=$(
    printf '%s\n' "$LOAD_LINES" |
        awk 'NF { count++ } END { print count + 0 }'
)

if [ "$LOAD_COUNT" -lt 1 ]; then
    fail no_load_segments
fi

while IFS= read -r line
do
    [ -n "$line" ] || continue

    flags=$(
        printf '%s\n' "$line" |
            awk '{
                flags = ""
                for (i = 7; i < NF; i++) {
                    if ($i ~ /^[RWE]+$/)
                        flags = flags $i
                }
                print flags
            }'
    )

    case "$flags" in
        *W*E*|*E*W*)
            fail writable_executable_load
            ;;
    esac
done <<LOAD_EOF
$LOAD_LINES
LOAD_EOF

# ---------------------------------------------------------------------------
# Section policy.
#
# No allocated section may be both writable and executable.
# ---------------------------------------------------------------------------

while IFS= read -r line
do
    [ -n "$line" ] || continue

    flags=$(
        printf '%s\n' "$line" |
            awk '{ for (i=1; i<=NF; i++) if ($i ~ /^[WAX]+$/) print $i }' |
            tail -n 1
    )

    case "$flags" in
        *W*X*|*X*W*)
            fail writable_executable_section
            ;;
    esac
done <<SECTION_EOF
$(
    printf '%s\n' "$SECTIONS" |
        grep -E '^[[:space:]]*\[[[:space:]]*[0-9]+\]' || true
)
SECTION_EOF

printf 'elf_hardening_status=0\n'
exit 0
