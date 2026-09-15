# Common build rules for Small_SoC programs.
# A program directory sets PROG (and optionally SRCS, CFLAGS_EXTRA) and
# includes this file. Output: $(PROG).elf, .bin, .hex, .lst
#
#   make            build hardware image ($(PROG).hex)
#   make sim        build with -DSIM_BUILD (short delays, self-terminating) and run in xsim
#   make clean

SW_DIR     := $(dir $(lastword $(MAKEFILE_LIST)))
ROOT       := $(abspath $(SW_DIR)/..)
COMMON     := $(SW_DIR)common
PYTHON    ?= py -3
PREFIX    ?= riscv-none-elf-
CC         = $(PREFIX)gcc
OBJCOPY    = $(PREFIX)objcopy
OBJDUMP    = $(PREFIX)objdump

ARCH       = -march=rv32i_zicsr_zifencei -mabi=ilp32
CFLAGS     = $(ARCH) -Os -g -Wall -Wextra -ffreestanding -fno-common \
             -I$(COMMON) $(CFLAGS_EXTRA)
LDFLAGS    = $(ARCH) -nostdlib -nostartfiles -static -T $(COMMON)/link.ld \
             -Wl,--gc-sections -Wl,-Map,$(PROG).map
LDLIBS     = -lgcc

SRCS      ?= main.c
COMMON_SRCS = $(COMMON)/crt0.S $(COMMON)/trap.S $(COMMON)/uart.c $(COMMON)/timer.c $(COMMON)/trap.c

all: $(PROG).hex $(PROG).lst

$(PROG).elf: $(SRCS) $(COMMON_SRCS) $(COMMON)/soc.h $(COMMON)/link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(COMMON_SRCS) $(SRCS) $(LDLIBS) -o $@

%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

%.hex: %.bin
	$(PYTHON) $(ROOT)/scripts/bin2hex.py $< $@

%.lst: %.elf
	$(OBJDUMP) -d -S $< > $@

# ---- simulation build: same sources, SIM_BUILD defined, run in xsim ----
$(PROG)_sim.elf: $(SRCS) $(COMMON_SRCS) $(COMMON)/soc.h $(COMMON)/link.ld
	$(CC) $(CFLAGS) -DSIM_BUILD $(LDFLAGS) $(COMMON_SRCS) $(SRCS) $(LDLIBS) -o $@

sim: $(PROG)_sim.hex
	$(PYTHON) $(ROOT)/scripts/run_prog.py $< $(SIM_ARGS)

clean:
	-rm -f $(PROG).elf $(PROG).bin $(PROG).hex $(PROG).lst $(PROG).map \
	       $(PROG)_sim.elf $(PROG)_sim.bin $(PROG)_sim.hex $(PROG)_sim.map

.PHONY: all sim clean
.PRECIOUS: %.elf %.bin

# copy the hardware image into the Vivado source tree (BRAM init for the bitstream)
install: $(PROG).hex
	cp $(PROG).hex $(ROOT)/rtl/program.hex
.PHONY: install
