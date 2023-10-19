MKIMG = ../mkimage_imx8

CC ?= gcc
REV ?= A0
OEI ?= NO
MSEL ?= 0
CFLAGS ?= -O2 -Wall -std=c99 -static
INCLUDE = ./lib

#define the F(Q)SPI header file
QSPI_HEADER = ../scripts/fspi_header
QSPI_PACKER = ../scripts/fspi_packer.sh
QSPI_FCB_GEN = ../scripts/fspi_fcb_gen.sh
PAD_IMAGE = ../scripts/pad_image.sh

ifneq ($(wildcard /usr/bin/rename.ul),)
    RENAME = rename.ul
else
    RENAME = rename
endif

LC_REVISION = $(shell echo $(REV) | tr ABC abc)

ifeq ($(SOC),iMX95)
AHAB_IMG = mx95$(LC_REVISION)-ahab-container.img
SPL_LOAD_ADDR ?= 0x4aa00000		# For singleboot, non-SCMI SPL, use NPU SRAM
SPL_LOAD_ADDR_M33_VIEW ?= 0x20480000 	# For lpboot, SCMI SPL
ATF_LOAD_ADDR ?= 0x204A0000
UBOOT_LOAD_ADDR ?= 0x90200000
MCU_TCM_ADDR ?= 0x1FFC0000		# 256KB TCM
MCU_TCM_ADDR_ACORE_VIEW ?= 0x201C0000
LPDDR_TYPE  ?= lpddr5
LPDDR_FW_VERSION ?= _v202306
SPL_A55_IMG ?= u-boot-spl-ddr-v2.bin
KERNEL_DTB ?= imx95-19x19-evk.dtb   # Used by kernel authentication
KERNEL_DTB_ADDR ?= 0x93000000
KERNEL_ADDR ?= 0x90400000

else ifeq ($(SOC),iMX91)
AHAB_IMG = mx93$(LC_REVISION)-ahab-container.img
SPL_LOAD_ADDR ?= 0x204A0000
ATF_LOAD_ADDR ?= 0x204C0000
UBOOT_LOAD_ADDR ?= 0x80200000
MCU_TCM_ADDR ?= 0x1FFE0000		# Not Valid for iMX91
MCU_TCM_ADDR_ACORE_VIEW ?= 0x201E0000	# Not Valid for iMX91
LPDDR_FW_VERSION ?= _v202201
SPL_A55_IMG ?= u-boot-spl-ddr.bin
KERNEL_DTB ?= imx91-11x11-evk.dtb   # Used by kernel authentication
KERNEL_DTB_ADDR ?= 0x83000000
KERNEL_ADDR ?= 0x80400000

else # iMX93
AHAB_IMG = mx93$(LC_REVISION)-ahab-container.img
SPL_LOAD_ADDR ?= 0x2049A000
SPL_LOAD_ADDR_M33_VIEW ?= 0x3049A000
ATF_LOAD_ADDR ?= 0x204E0000
UBOOT_LOAD_ADDR ?= 0x80200000
MCU_TCM_ADDR ?= 0x1FFE0000		# 128KB TCM
MCU_TCM_ADDR_ACORE_VIEW ?= 0x201E0000
LPDDR_FW_VERSION ?= _v202201
SPL_A55_IMG ?= u-boot-spl-ddr.bin
KERNEL_DTB ?= imx93-11x11-evk.dtb   # Used by kernel authentication
KERNEL_DTB_ADDR ?= 0x83000000
KERNEL_ADDR ?= 0x80400000
# This Capsule_GUID is reserved by NXP
CAPSULE_GUID = bc550d86-da26-4b70-ac05-2a448eda6f21

endif

FCB_LOAD_ADDR ?= $(ATF_LOAD_ADDR)
MCU_IMG = m33_image.bin
M7_IMG = m7_image.bin
TEE ?= tee.bin
TEE_LOAD_ADDR ?= 0x96000000
MCU_XIP_ADDR ?= 0x28032000 # Point entry of m33 in flexspi0 nor flash
M33_IMAGE_XIP_OFFSET ?= 0x31000 # 1st container offset is 0x1000 when boot device is flexspi0 nor
				# flash, actually the m33_image.bin is in 0x31000 + 0x1000 = 0x32000.
M7_TCM_ADDR ?= 0x0
M7_TCM_ADDR_ALIAS ?= 0x303C0000
M7_DDR_ADDR ?= 0x88000000

OEI_A55_IMG ?= oei.bin.ca55
OEI_M33_IMG ?= oei.bin.cm33
OEI_A55_LOAD_ADDR ?= 0x20498000
OEI_A55_ENTR_ADDR ?= $(OEI_A55_LOAD_ADDR)
OEI_M33_LOAD_ADDR ?= 0x1ffc0000
OEI_M33_ENTR_ADDR ?= 0x1ffc0001	# = real entry address (0x1ffc0000) + 1

ifeq ($(OEI),YES)
OEI_A55_DDR = oei-a55-ddr.bin
OEI_M33_DDR = oei-m33-ddr.bin
OEI_OPT_A55 ?= -oei $(OEI_A55_DDR) a55 $(OEI_A55_ENTR_ADDR) $(OEI_A55_LOAD_ADDR)
OEI_OPT_M33 ?= -oei $(OEI_M33_DDR) m33 $(OEI_M33_ENTR_ADDR) $(OEI_M33_LOAD_ADDR)
SPL_A55_IMG = u-boot-spl.bin	# SPL without no ddrfw
else
OEI_A55_DDR =
OEI_M33_DDR =
OEI_OPT_A55 ?=
OEI_OPT_M33 ?=
endif

###########################
# Append container macro
#
# $(1) - container to append, usually: u-boot-atf-container.img
# $(2) - the page at which the container must be append, usually: 1
###########################
define append_container
	@cp flash.bin boot-spl-container.img
	@flashbin_size=`wc -c flash.bin | awk '{print $$1}'`; \
                   psize=$$((0x400 * $(2))); \
                   pad_cnt=$$(((flashbin_size + psize - 1) / psize)); \
                   echo "append $(1) at $$pad_cnt KB, psize=$$psize"; \
                   dd if=$(1) of=flash.bin bs=1K seek=$$pad_cnt;
endef

define append_fcb
	@mv flash.bin flash.tmp
	@dd if=fcb.bin of=flash.bin bs=1k seek=1
	@dd if=flash.tmp of=flash.bin bs=1k seek=4
	@rm flash.tmp
	@echo "Append FCB to flash.bin"
endef

FORCE:

lpddr4_imem_1d = lpddr4_imem_1d$(LPDDR_FW_VERSION).bin
lpddr4_dmem_1d = lpddr4_dmem_1d$(LPDDR_FW_VERSION).bin
lpddr4_imem_2d = lpddr4_imem_2d$(LPDDR_FW_VERSION).bin
lpddr4_dmem_2d = lpddr4_dmem_2d$(LPDDR_FW_VERSION).bin
lpddr4_imem_qb = lpddr4_imem_qb$(LPDDR_FW_VERSION).bin
lpddr4_dmem_qb = lpddr4_dmem_qb$(LPDDR_FW_VERSION).bin
lpddr4_qb_data = lpddr4_qb_data.bin

lpddr_imem = $(LPDDR_TYPE)_imem$(LPDDR_FW_VERSION).bin
lpddr_dmem = $(LPDDR_TYPE)_dmem$(LPDDR_FW_VERSION).bin

fw-header.bin: $(lpddr_imem) $(lpddr_dmem)
	@imem_size=`wc -c $(lpddr_imem) | awk '{printf "%.8x", $$1}' | sed -e 's/\(..\)\(..\)\(..\)\(..\)/\4\3\2\1/'`; \
		echo $$imem_size | xxd -r -p >  fw-header.bin
	@dmem_size=`wc -c $(lpddr_dmem) | awk '{printf "%.8x", $$1}' | sed -e 's/\(..\)\(..\)\(..\)\(..\)/\4\3\2\1/'`; \
		echo $$dmem_size | xxd -r -p >> fw-header.bin

define append_ddrfw_v2
	@dd if=$(1) of=$(1)-pad bs=4 conv=sync
	@cat $(1)-pad fw-header.bin $(lpddr_imem) $(lpddr_dmem) > $(2).unaligned
	@dd if=$(2).unaligned of=$(2) bs=8 conv=sync
	@rm -f $(1)-pad $(2).unaligned fw-header.bin
endef

oei-a55-ddr.bin: $(OEI_A55_IMG) $(lpddr_imem) $(lpddr_dmem) fw-header.bin
	$(call append_ddrfw_v2,$(OEI_A55_IMG),oei-a55-ddr.bin)

oei-m33-ddr.bin: $(OEI_M33_IMG) $(lpddr_imem) $(lpddr_dmem) fw-header.bin
	$(call append_ddrfw_v2,$(OEI_M33_IMG),oei-m33-ddr.bin)

u-boot-spl-ddr-v2.bin: u-boot-spl.bin $(lpddr_imem) $(lpddr_dmem) fw-header.bin
	$(call append_ddrfw_v2,u-boot-spl.bin,u-boot-spl-ddr-v2.bin)

u-boot-spl-ddr.bin: u-boot-spl.bin $(lpddr4_imem_1d) $(lpddr4_dmem_1d) $(lpddr4_imem_2d) $(lpddr4_dmem_2d)
	@objcopy -I binary -O binary --pad-to 0x8000 --gap-fill=0x0 $(lpddr4_imem_1d) lpddr4_pmu_train_1d_imem_pad.bin
	@objcopy -I binary -O binary --pad-to 0x4000 --gap-fill=0x0 $(lpddr4_dmem_1d) lpddr4_pmu_train_1d_dmem_pad.bin
	@objcopy -I binary -O binary --pad-to 0x8000 --gap-fill=0x0 $(lpddr4_imem_2d) lpddr4_pmu_train_2d_imem_pad.bin
	@cat lpddr4_pmu_train_1d_imem_pad.bin lpddr4_pmu_train_1d_dmem_pad.bin > lpddr4_pmu_train_1d_fw.bin
	@cat lpddr4_pmu_train_2d_imem_pad.bin $(lpddr4_dmem_2d) > lpddr4_pmu_train_2d_fw.bin
	@dd if=u-boot-spl.bin of=u-boot-spl-pad.bin bs=4 conv=sync
	@cat u-boot-spl-pad.bin lpddr4_pmu_train_1d_fw.bin lpddr4_pmu_train_2d_fw.bin > u-boot-spl-ddr.bin
	@rm -f u-boot-spl-pad.bin lpddr4_pmu_train_1d_fw.bin lpddr4_pmu_train_2d_fw.bin
	@rm -f lpddr4_pmu_train_1d_imem_pad.bin lpddr4_pmu_train_1d_dmem_pad.bin lpddr4_pmu_train_2d_imem_pad.bin

u-boot-spl-ddr-qb.bin: u-boot-spl.bin $(lpddr4_imem_qb) $(lpddr4_dmem_qb) $(lpddr4_qb_data)
	@objcopy -I binary -O binary --pad-to 0x8000 --gap-fill=0x0 $(lpddr4_imem_qb) lpddr4_pmu_qb_imem_pad.bin
	@objcopy -I binary -O binary --pad-to 0x4000 --gap-fill=0x0 $(lpddr4_dmem_qb) lpddr4_pmu_qb_dmem_pad.bin
	@cat lpddr4_pmu_qb_imem_pad.bin lpddr4_pmu_qb_dmem_pad.bin > lpddr4_pmu_qb_fw.bin
	@dd if=u-boot-spl.bin of=u-boot-spl-pad.bin bs=4 conv=sync
	@cat u-boot-spl-pad.bin lpddr4_pmu_qb_fw.bin $(lpddr4_qb_data) > u-boot-spl-ddr-qb.bin
	@rm -f u-boot-spl-pad.bin lpddr4_pmu_qb_imem_pad.bin lpddr4_pmu_qb_dmem_pad.bin lpddr4_pmu_qb_fw.bin

u-boot-hash.bin: u-boot.bin
	./$(MKIMG) -commit > head.hash
	@cat u-boot.bin head.hash > u-boot-hash.bin

u-boot-atf.bin: u-boot-hash.bin bl31.bin
	@cp bl31.bin u-boot-atf.bin
	@dd if=u-boot-hash.bin of=u-boot-atf.bin bs=1K seek=128

u-boot-atf.itb: u-boot-hash.bin bl31.bin
	./$(PAD_IMAGE) bl31.bin
	./$(PAD_IMAGE) u-boot-hash.bin
	TEE_LOAD_ADDR=$(TEE_LOAD_ADDR) ./mkimage_fit_atf.sh > u-boot.its;
	./mkimage_uboot -E -p 0x3000 -f u-boot.its u-boot-atf.itb;
	@rm -f u-boot.its

u-boot-atf-container.img: bl31.bin u-boot-hash.bin
	if [ -f $(TEE) ]; then \
		if [ $(shell echo $(ROLLBACK_INDEX_IN_CONTAINER)) ]; then \
			./$(MKIMG) -soc IMX9 -sw_version $(ROLLBACK_INDEX_IN_CONTAINER) -c \
				   -ap bl31.bin a55 $(ATF_LOAD_ADDR) \
				   -ap u-boot-hash.bin a55 $(UBOOT_LOAD_ADDR) \
				   -ap $(TEE) a55 $(TEE_LOAD_ADDR) \
				   -out u-boot-atf-container.img; \
		else \
			./$(MKIMG) -soc IMX9 -c \
				   -ap bl31.bin a55 $(ATF_LOAD_ADDR) \
				   -ap u-boot-hash.bin a55 $(UBOOT_LOAD_ADDR) \
				   -ap $(TEE) a55 $(TEE_LOAD_ADDR) -out u-boot-atf-container.img; \
		fi; \
	else \
		./$(MKIMG) -soc IMX9 -c \
			   -ap bl31.bin a55 $(ATF_LOAD_ADDR) \
			   -ap u-boot-hash.bin a55 $(UBOOT_LOAD_ADDR) \
			   -out u-boot-atf-container.img; \
	fi

u-boot-atf-container-spinand.img: bl31.bin u-boot-hash.bin
	if [ -f $(TEE) ]; then \
		if [ $(shell echo $(ROLLBACK_INDEX_IN_CONTAINER)) ]; then \
			./$(MKIMG) -soc IMX9 -sw_version $(ROLLBACK_INDEX_IN_CONTAINER) \
				   -dev nand 4K -c \
				   -ap bl31.bin a55 $(ATF_LOAD_ADDR) \
				   -ap u-boot-hash.bin a55 $(UBOOT_LOAD_ADDR) \
				   -ap $(TEE) a55 $(TEE_LOAD_ADDR) \
				   -out u-boot-atf-container-spinand.img; \
		else \
			./$(MKIMG) -soc IMX9 -dev nand 4K -c \
				   -ap bl31.bin a55 $(ATF_LOAD_ADDR) \
				   -ap u-boot-hash.bin a55 $(UBOOT_LOAD_ADDR) \
				   -ap $(TEE) a55 $(TEE_LOAD_ADDR) \
				   -out u-boot-atf-container-spinand.img; \
		fi; \
	else \
		./$(MKIMG) -soc IMX9 -dev nand 4K -c \
			   -ap bl31.bin a55 $(ATF_LOAD_ADDR) \
			   -ap u-boot-hash.bin a55 $(UBOOT_LOAD_ADDR) \
			   -out u-boot-atf-container-spinand.img; \
	fi

fcb.bin: FORCE
	./$(QSPI_FCB_GEN) $(QSPI_HEADER)

flash_fw.bin: FORCE
	@$(MAKE) --no-print-directory -f soc.mak flash_singleboot
	@mv -f flash.bin $@

.PHONY: clean nightly
clean:
	@rm -f $(MKIMG) u-boot-atf-container.img u-boot-spl-ddr.bin u-boot-spl-ddr-qb.bin u-boot-hash.bin
	@rm -rf extracted_imgs
	@echo "imx9 clean done"

# Add for System ready
ifeq ($(TEE),tee.bin-stmm)
KEY_EXISTS = $(shell if ls *CRT.* &> /dev/null 2>&1; then echo "exist"; else echo "noexist"; fi)
capsule_key:
ifeq ($(KEY_EXISTS),exist)
	@echo "****************************************************************"
	@echo "Key $(shell ls CRT.*) already existed"
	@echo "If you not wanna use new Key, please not run target: capsule_key"
	@echo "Otherwise, please delete CRT.* and re-run capsule_key"
	@echo "****************************************************************"
	@exit 1
endif
	openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=CRT/ -keyout CRT.key -out CRT.crt -nodes -days 365
	cert-to-efi-sig-list CRT.crt CRT.esl

delete_capsule_key:
	@rm -rf CRT.*

overlay: u-boot.bin
	./$(MKIMG) -soc IMX9 -split u-boot.bin
	dtc -@ -I dts -O dtb -o signature.dtbo signature.dts
	fdtoverlay -i gen-uboot.dtb -o gen-uboot.dtb signature.dtbo
	@cat gen-u-boot-nodtb.bin gen-uboot.dtb > gen-u-boot.bin
	@mv -f gen-u-boot.bin u-boot.bin

flash_singleboot_stmm_capsule: overlay flash_singleboot
	./mkeficapsule flash.bin --monotonic-count 1 \
		--guid $(CAPSULE_GUID) \
		--private-key CRT.key \
		--certificate CRT.crt \
		--index 1 --instance 0 \
		capsule1.bin

flash_singleboot_stmm: flash_singleboot_stmm_capsule
endif


flash_singleboot: $(MKIMG) $(AHAB_IMG) $(SPL_A55_IMG) u-boot-atf-container.img $(OEI_A55_DDR)
	./$(MKIMG) -soc IMX9 -append $(AHAB_IMG) -c $(OEI_OPT_A55) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR) -out flash.bin
	$(call append_container,u-boot-atf-container.img,1)

flash_singleboot_no_ahabfw: $(MKIMG) $(SPL_A55_IMG) u-boot-atf-container.img $(OEI_A55_DDR)
	./$(MKIMG) -soc IMX9 -c $(OEI_OPT_A55) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR) -out flash.bin
	$(call append_container,u-boot-atf-container.img,1)

flash_singleboot_spinand: $(MKIMG) $(AHAB_IMG) $(SPL_A55_IMG) u-boot-atf-container-spinand.img $(OEI_OPT_A55) flash_fw.bin
	./$(MKIMG) -soc IMX9 -dev nand 4K -append $(AHAB_IMG) -c $(OEI_OPT_A55) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR) -out flash.bin
	$(call append_container,u-boot-atf-container-spinand.img,4)

flash_singleboot_spinand_fw: flash_fw.bin
	@mv -f flash_fw.bin flash.bin

flash_singleboot_qb: $(MKIMG) $(AHAB_IMG) u-boot-spl-ddr-qb.bin u-boot-atf-container.img
	./$(MKIMG) -soc IMX9 -append $(AHAB_IMG) -c -ap u-boot-spl-ddr-qb.bin a55 $(SPL_LOAD_ADDR) -out flash.bin
	$(call append_container,u-boot-atf-container.img,1)

flash_singleboot_flexspi: $(MKIMG) $(AHAB_IMG) $(OEI_A55_DDR) $(SPL_A55_IMG) u-boot-atf-container.img fcb.bin
	./$(MKIMG) -soc IMX9 -dev flexspi -append $(AHAB_IMG) -c $(OEI_OPT_A55) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR) \
		   -fcb fcb.bin $(FCB_LOAD_ADDR) -out flash.bin
	$(call append_container,u-boot-atf-container.img,1)
	$(call append_fcb)

flash_singleboot_m33: $(MKIMG) $(AHAB_IMG) u-boot-atf-container.img $(MCU_IMG) $(SPL_A55_IMG) $(OEI_A55_DDR)
	./$(MKIMG) -soc IMX9 -append $(AHAB_IMG) -c $(OEI_OPT_A55) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) $(MCU_TCM_ADDR_ACORE_VIEW) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR) -out flash.bin
	$(call append_container,u-boot-atf-container.img,1)

flash_singleboot_m33_no_ahabfw: $(MKIMG) u-boot-atf-container.img $(MCU_IMG) $(SPL_A55_IMG) $(OEI_A55_DDR)
	./$(MKIMG) -soc IMX9 -c $(OEI_OPT_A55) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) $(MCU_TCM_ADDR_ACORE_VIEW) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR) -out flash.bin
	$(call append_container,u-boot-atf-container.img,1)

flash_singleboot_m33_flexspi: $(MKIMG) $(AHAB_IMG) $(UPOWER_IMG) u-boot-atf-container.img $(MCU_IMG) $(SPL_A55_IMG) $(OEI_A55_DDR) fcb.bin
	./$(MKIMG) -soc IMX9 -dev flexspi -append $(AHAB_IMG) -c $(OEI_OPT_A55) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) $(MCU_TCM_ADDR_ACORE_VIEW) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR) \
		   -fcb fcb.bin $(FCB_LOAD_ADDR) -out flash.bin
	$(call append_container,u-boot-atf-container.img,1)
	$(call append_fcb)

flash_singleboot_all: $(MKIMG) $(AHAB_IMG) u-boot-atf-container.img $(MCU_IMG) $(M7_IMG) $(SPL_A55_IMG) $(OEI_A55_DDR)
	./$(MKIMG) -soc IMX9 -append $(AHAB_IMG) -c $(OEI_OPT_A55) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) $(MCU_TCM_ADDR_ACORE_VIEW) \
		   -m7 $(M7_IMG) 0 $(M7_TCM_ADDR) $(M7_TCM_ADDR_ALIAS) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR) -out flash.bin
	$(call append_container,u-boot-atf-container.img,1)

flash_singleboot_all_no_ahabfw: $(MKIMG) u-boot-atf-container.img $(MCU_IMG) $(M7_IMG) $(SPL_A55_IMG) $(OEI_A55_DDR)
	./$(MKIMG) -soc IMX9 -c $(OEI_OPT_A55) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) $(MCU_TCM_ADDR_ACORE_VIEW) \
		   -m7 $(M7_IMG) 0 $(M7_TCM_ADDR) $(M7_TCM_ADDR_ALIAS) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR) -out flash.bin
	$(call append_container,u-boot-atf-container.img,1)

flash_lpboot: $(MKIMG) $(AHAB_IMG) $(MCU_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -append $(AHAB_IMG) -c $(OEI_OPT_M33) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) -out flash.bin

flash_lpboot_no_ahabfw: $(MKIMG) $(MCU_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -c $(OEI_OPT_M33) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) -out flash.bin

flash_lpboot_a55: $(MKIMG) $(AHAB_IMG) $(MCU_IMG) $(SPL_A55_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -append $(AHAB_IMG) -c $(OEI_OPT_M33) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR_M33_VIEW) -out flash.bin

flash_lpboot_a55_no_ahabfw: $(MKIMG) $(MCU_IMG) $(SPL_A55_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -c $(OEI_OPT_M33) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR_M33_VIEW) -out flash.bin

flash_lpboot_all: $(MKIMG) $(AHAB_IMG) $(MCU_IMG) $(M7_IMG) $(SPL_A55_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -append $(AHAB_IMG) -c $(OEI_OPT_M33) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -m7 $(M7_IMG) 0 $(M7_TCM_ADDR) $(M7_TCM_ADDR_ALIAS) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR_M33_VIEW) -out flash.bin

flash_lpboot_all_no_ahabfw: $(MKIMG) $(MCU_IMG) $(M7_IMG) $(SPL_A55_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -c $(OEI_OPT_M33) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -m7 $(M7_IMG) 0 $(M7_TCM_ADDR) $(M7_TCM_ADDR_ALIAS) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR_M33_VIEW) -out flash.bin

flash_lpboot_flexspi: $(MKIMG) $(AHAB_IMG) $(MCU_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -dev flexspi -append $(AHAB_IMG) -c $(OEI_OPT_M33) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) -out flash.bin
	./$(QSPI_PACKER) $(QSPI_HEADER)

flash_lpboot_flexspi_no_ahabfw: $(MKIMG) $(MCU_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -dev flexspi -c $(OEI_OPT_M33) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) -out flash.bin
	./$(QSPI_PACKER) $(QSPI_HEADER)

flash_lpboot_flexspi_a55: $(MKIMG) $(AHAB_IMG) $(MCU_IMG) $(SPL_A55_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -dev flexspi -append $(AHAB_IMG) -c $(OEI_OPT_M33) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR_M33_VIEW) -out flash.bin
	./$(QSPI_PACKER) $(QSPI_HEADER)

flash_lpboot_flexspi_a55_no_ahabfw: $(MKIMG) $(MCU_IMG) $(SPL_A55_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -dev flexspi -c $(OEI_OPT_M33) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -ap  $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR_M33_VIEW) -out flash.bin
	./$(QSPI_PACKER) $(QSPI_HEADER)

flash_lpboot_flexspi_xip: $(MKIMG) $(AHAB_IMG) $(MCU_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -dev flexspi -append $(AHAB_IMG) -fileoff $(M33_IMAGE_XIP_OFFSET) \
		   -c $(OEI_OPT_M33) -m33 $(MCU_IMG) 0 $(MCU_XIP_ADDR) -out flash.bin
	./$(QSPI_PACKER) $(QSPI_HEADER)

flash_lpboot_sm_a55: $(MKIMG) $(AHAB_IMG) $(MCU_IMG) u-boot-atf-container.img $(SPL_A55_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -append $(AHAB_IMG) -c $(OEI_OPT_M33) -msel $(MSEL) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR_M33_VIEW) -out flash.bin
	$(call append_container,u-boot-atf-container.img,1)

flash_lpboot_sm_a55_no_ahabfw: $(MKIMG) $(MCU_IMG) u-boot-atf-container.img $(SPL_A55_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -c $(OEI_OPT_M33) -msel $(MSEL) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR_M33_VIEW) -out flash.bin
	$(call append_container,u-boot-atf-container.img,1)

flash_lpboot_sm_a55_flexspi: $(MKIMG) $(AHAB_IMG) $(MCU_IMG) $(SPL_A55_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -dev flexspi -append $(AHAB_IMG) -c $(OEI_OPT_M33) -msel $(MSEL) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR_M33_VIEW) -out flash.bin
	$(call append_container,u-boot-atf-container.img,1)
	./$(QSPI_PACKER) $(QSPI_HEADER)

flash_lpboot_sm: flash_lpboot

flash_lpboot_sm_no_ahabfw: flash_lpboot_no_ahabfw

flash_lpboot_sm_m7_no_ahabfw: $(MKIMG) $(MCU_IMG) $(M7_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -c $(OEI_OPT_M33) -msel $(MSEL) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -m7 $(M7_IMG) 0 $(M7_TCM_ADDR) $(M7_TCM_ADDR_ALIAS) -out flash.bin

flash_lpboot_sm_m7: $(MKIMG) $(MCU_IMG) $(M7_IMG) $(AHAB_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -append $(AHAB_IMG) -c $(OEI_OPT_M33) -msel $(MSEL) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -m7 $(M7_IMG) 0 $(M7_TCM_ADDR) $(M7_TCM_ADDR_ALIAS) -out flash.bin

# The diff with "flash_lpboot_sm_m7_no_ahabfw" is M7_TCM_ADDR vs M7_DDR_ADDR in -m7 option
flash_lpboot_sm_m7_ddr_no_ahabfw: $(MKIMG) $(MCU_IMG) $(M7_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -c $(OEI_OPT_M33) -msel $(MSEL) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -m7 $(M7_IMG) 0 $(M7_DDR_ADDR) $(M7_DDR_ADDR) -out flash.bin

# The diff with "flash_lpboot_sm_m7" is M7_TCM_ADDR vs M7_DDR_ADDR in -m7 option
flash_lpboot_sm_m7_ddr: $(MKIMG) $(MCU_IMG) $(M7_IMG) $(OEI_M33_DDR) $(AHAB_IMG)
	./$(MKIMG) -soc IMX9 -append $(AHAB_IMG) -c $(OEI_OPT_M33) -msel $(MSEL) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -m7 $(M7_IMG) 0 $(M7_DDR_ADDR) $(M7_DDR_ADDR) -out flash.bin

flash_lpboot_sm_all: $(MKIMG) $(AHAB_IMG) $(MCU_IMG) $(M7_IMG) u-boot-atf-container.img $(SPL_A55_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -append $(AHAB_IMG) -c $(OEI_OPT_M33) -msel $(MSEL) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -m7 $(M7_IMG) 0 $(M7_TCM_ADDR) $(M7_TCM_ADDR_ALIAS)  \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR_M33_VIEW) -out flash.bin
	$(call append_container,u-boot-atf-container.img,1)

flash_lpboot_sm_all_no_ahabfw: $(MKIMG) $(MCU_IMG) $(M7_IMG) u-boot-atf-container.img $(SPL_A55_IMG) $(OEI_M33_DDR)
	./$(MKIMG) -soc IMX9 -c $(OEI_OPT_M33) -msel $(MSEL) \
		   -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) \
		   -m7 $(M7_IMG) 0 $(M7_TCM_ADDR) $(M7_TCM_ADDR_ALIAS)  \
		   -ap $(SPL_A55_IMG) a55 $(SPL_LOAD_ADDR_M33_VIEW) -out flash.bin
	$(call append_container,u-boot-atf-container.img,1)

flash_sentinel: $(MKIMG) ahabfw.bin
	./$(MKIMG) -soc IMX9 -c -sentinel ahabfw.bin -out flash.bin

flash_kernel: $(MKIMG) Image $(KERNEL_DTB)
	./$(MKIMG) -soc IMX9 -c -ap Image a55 $(KERNEL_ADDR) --data $(KERNEL_DTB) a55 $(KERNEL_DTB_ADDR) -out flash.bin

flash_bootaux_cntr: $(MKIMG) $(MCU_IMG)
	./$(MKIMG) -soc IMX9 -c -m33 $(MCU_IMG) 0 $(MCU_TCM_ADDR) $(MCU_TCM_ADDR_ACORE_VIEW) -out flash.bin

flash_bootaux_cntr_xip: $(MKIMG) $(MCU_IMG)
	./$(MKIMG) -soc IMX9 -c -fileoff $(M33_IMAGE_XIP_OFFSET) -m33 $(MCU_IMG) 0 $(MCU_XIP_ADDR) -out flash.bin

parse_container: $(MKIMG) flash.bin
	./$(MKIMG) -soc IMX9 -parse flash.bin

extract: $(MKIMG) flash.bin
	./$(MKIMG) -soc IMX9 -extract flash.bin

ifneq ($(wildcard ../$(SOC_DIR)/scripts/autobuild.mak),)
$(info include autobuild.mak)
include ../$(SOC_DIR)/scripts/autobuild.mak
endif
