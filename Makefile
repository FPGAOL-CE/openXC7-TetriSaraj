PREFIX ?= /snap/openxc7/current
DB_DIR=${PREFIX}/opt/nextpnr-xilinx/external/prjxray-db
CHIPDB=../chipdb

#PART = xc7a100tcsg324-1
PART = xc7a35tcpg236-1

CURR_DIR := $(CURDIR)
SW_DIR := $(CURR_DIR)/2.sw

SRC_DIR0 = 1.hw
SRC_DIR1 = 1.hw/ip.cpu
SRC_DIR2 = 1.hw/ip.vga
SRC_DIR3 = 1.hw/ip.misc
SRC_DIR4 = 1.hw/ip.display

SRC_FILES0 := $(wildcard $(CURR_DIR)/$(SRC_DIR0)/*.v)
SRC_FILES1a := $(CURR_DIR)/$(SRC_DIR1)/picorv32.v
SRC_FILES1b := $(CURR_DIR)/$(SRC_DIR1)/picosoc_noflash.v
SRC_FILES2 := $(wildcard $(CURR_DIR)/$(SRC_DIR2)/*.v)
SRC_FILES3 := $(wildcard $(CURR_DIR)/$(SRC_DIR3)/*.v)
SRC_FILES4 := $(wildcard $(CURR_DIR)/$(SRC_DIR4)/*.v)
SRC_FILES5 := $(wildcard $(CURR_DIR)/*.v)

XDC_FILE := $(CURR_DIR)/$(SRC_DIR0)/top.basys3.xdc
TOP_FILE := $(CURR_DIR)/$(SRC_DIR0)/top.basys3.v

.PHONY: all
all: top.bit

.PHONY: program
program: top.bit
	openFPGALoader --board basys3 --bitstream $<
	
top.json: $(TOP_FILE) $(SRC_FILES1b) $(SRC_FILES1a) $(SRC_FILES2) $(SRC_FILES3) $(SRC_FILES4) $(SRC_FILES5)
	yosys -p "synth_xilinx -flatten -abc9 -arch xc7 -top top; write_json top.json" $(TOP_FILE) $(SRC_FILES1b) $(SRC_FILES1a) $(SRC_FILES2) $(SRC_FILES3) $(SRC_FILES4) $(SRC_FILES5)

# The chip database only needs to be generated once
# that is why we don't clean it with make clean
${CHIPDB}/${PART}.bin:
	python3 ${PREFIX}/opt/nextpnr-xilinx/python/bbaexport.py --device ${PART} --bba ${PART}.bba
	bbasm -l ${PART}.bba ${CHIPDB}/${PART}.bin
	rm -f ${PART}.bba
	
	
top.fasm: top.json ${CHIPDB}/${PART}.bin
	nextpnr-xilinx --chipdb ${CHIPDB}/${PART}.bin --xdc $(XDC_FILE) --json top.json --fasm $@ --verbose --debug
	
top.frames: top.fasm
	fasm2frames --part ${PART} --db-root ${DB_DIR}/artix7 $< > $@ #FIXME: fasm2frames should be on PATH

top.bit: top.frames
	xc7frames2bit --part_file ${DB_DIR}/artix7/${PART}/part.yaml --part_name ${PART} --frm_file $< --output_file $@
	
	#Install gcc package: apt install gcc-riscv64-unknown-elf
CROSS=riscv64-unknown-elf-
CFLAGS=



hex: $(SW_DIR)/main.elf
	$(CROSS)objcopy -O verilog $< $(SW_DIR)/main.hex

firmware: $(SW_DIR)/main.elf
	$(CROSS)objcopy -O binary $< $(SW_DIR)/main.bin
	python progmem.py

$(SW_DIR)/main.elf: $(SW_DIR)/main.lds $(SW_DIR)/start.s $(SW_DIR)/main.c $(SW_DIR)/uart.c $(SW_DIR)/uart.h
	$(CROSS)gcc $(CFLAGS) -march=rv32im -mabi=ilp32 -Wl,--build-id=none,-Bstatic,-T,$(SW_DIR)/main.lds,-Map,$(SW_DIR)/main.map,--strip-debug -ffreestanding -nostdlib -o $@ $(SW_DIR)/start.s $(SW_DIR)/main.c $(SW_DIR)/uart.c

$(SW_DIR)/main.lds: $(SW_DIR)/sections.lds
	$(CROSS)cpp -P -o $@ $<

.PHONY: clean
clean:
	@rm -f *.bit
	@rm -f *.frames
	@rm -f *.fasm
	@rm -f *.json
clean_fw:
	rm -f $(CURR_DIR)/2.sw/main.elf
	rm -f $(CURR_DIR)/2.sw/main.lds
	rm -f $(CURR_DIR)/2.sw/main.map
	rm -f $(CURR_DIR)/2.sw/main.bin
	rm -f progmem.v
	rm -f firmware.hex
	rm -f $(CURR_DIR)/2.sw/main.hex