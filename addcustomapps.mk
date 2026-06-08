# =============================================================================
# Makefile.custom — Custom app builds for QNX CTI
# Included by src/Makefile automatically.
# =============================================================================

ifeq ($(TARGET),qemu)
    CC_TARGET = x86_64
else
    CC_TARGET = $(QNX_ARCH)le
endif

STAGE_DIR  = $(CURDIR)/stage/nto/$(CC_TARGET)/usr
APK_STAGE  = $(CURDIR)/../apk/stage/apk_root/usr
HOST_MAKE  := $(shell which make)
QNX_TARGET_DIR = $(CURDIR)/../qnx800/target/qnx

# Host Qt6 tools path
QT_HOST_PATH ?= /home/zee/Qt/6.10.2/gcc_64


# ---------------------------------------------------------------------------
# adding other cmakes for other applications & PKGS append
# ---------------------------------------------------------------------------
include addclusterapp.mk

# appending on the main src make file PKGS variable
# PKGS += mycustomapps
# PKGS += clusterapp

# ---------------------------------------------------------------------------
# Helper: emit a qcc/q++ wrapper script.
# ---------------------------------------------------------------------------
define make_c_wrapper
	@echo '#!/bin/bash' > $(1)/qcc-wrapper.sh
	@echo 'exec qcc -Vgcc_nto$(CC_TARGET) -D_QNX_SOURCE $(2) "$$@"' \
	    >> $(1)/qcc-wrapper.sh
	@chmod +x $(1)/qcc-wrapper.sh
endef

# libc++ path MUST come before any other -I flags so <cerrno>/<cmath> wrappers
# are found first.  Also undefine the QNX math.h macros that break libc++.
define make_cxx_wrapper
	@rm -f $(1)/qxx-wrapper.sh
	@echo '#!/bin/bash' > $(1)/qxx-wrapper.sh
	@echo 'exec q++ \
		-Vgcc_nto$(CC_TARGET)_cxx \
		-D_QNX_SOURCE \
		-D_HAS_CONDITIONAL_EXPLICIT=0 \
		-std=c++17 \
		-isystem $(QNX_TARGET_DIR)/usr/include/c++/v1 \
		-isystem $(QNX_TARGET_DIR)/usr/include \
		-isystem $(QNX_TARGET_DIR)/$(CC_TARGET)/usr/include \
		$(2) "$$@"' \
		>> $(1)/qxx-wrapper.sh
	@chmod +x $(1)/qxx-wrapper.sh
endef

# ---------------------------------------------------------------------------
# myapp — Qt CalculatorApp
# ---------------------------------------------------------------------------
MYAPP_DIR  = /home/zee/ITI_Files/QT/QT_Cpp_GUIs/CalculatorApp
MYAPP_DEPS = 

source/myapp-ready:
	@mkdir -p source
	@if [ ! -d "$(MYAPP_DIR)" ]; then \
	    echo "ERROR: $(MYAPP_DIR) does not exist."; \
	    exit 1; \
	fi
	@touch $@

source/myapp-built-$(QNX_ARCH): source/myapp-ready $(MYAPP_DEPS)
	@rm -f $(MYAPP_DIR)/qcc-wrapper.sh $(MYAPP_DIR)/qxx-wrapper.sh
	$(call make_c_wrapper,$(MYAPP_DIR),\
	    -L$(STAGE_DIR)/lib \
	    -L$(APK_STAGE)/lib)
	$(call make_cxx_wrapper,$(MYAPP_DIR),\
	    -L$(STAGE_DIR)/lib \
	    -L$(APK_STAGE)/lib)

	rm -rf $(MYAPP_DIR)/build
	cmake -B $(MYAPP_DIR)/build -S $(MYAPP_DIR) \
		-DCMAKE_SYSTEM_NAME=QNX \
		-DCMAKE_C_COMPILER=$(MYAPP_DIR)/qcc-wrapper.sh \
		-DCMAKE_CXX_COMPILER=$(MYAPP_DIR)/qxx-wrapper.sh \
		-DCMAKE_INSTALL_PREFIX=$(STAGE_DIR) \
		-DCMAKE_PREFIX_PATH="$(STAGE_DIR);$(APK_STAGE)" \
		-DQt6_DIR=$(APK_STAGE)/lib/cmake/Qt6 \
		-DCMAKE_MAKE_PROGRAM=$(HOST_MAKE) \
		-DQT_HOST_PATH=$(QT_HOST_PATH) \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_CXX_FLAGS="-Uisnan -Uisinf -Uisfinite -Usignbit -Uisnormal -Ufpclassify" \
		-DCMAKE_FIND_ROOT_PATH="$(APK_STAGE);$(STAGE_DIR)" \
		-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
		-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
		-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
		-DHAVE_EGL=TRUE \
		-DHAVE_GLESv2=TRUE \
		-DEGL_INCLUDE_DIR:PATH=$(APK_STAGE)/include \
		-DEGL_LIBRARY:FILEPATH=$(APK_STAGE)/lib/libEGL.so \
		-DGLESv2_INCLUDE_DIR:PATH=$(APK_STAGE)/include \
		-DGLESv2_LIBRARY:FILEPATH=$(APK_STAGE)/lib/libGLESv2.so \
		-DCMAKE_EXE_LINKER_FLAGS="-L$(APK_STAGE)/lib -L$(STAGE_DIR)/lib -Wl,--allow-shlib-undefined -Wl,-rpath-link,$(APK_STAGE)/lib" \
		-DCMAKE_SHARED_LINKER_FLAGS="-L$(APK_STAGE)/lib -L$(STAGE_DIR)/lib -Wl,--allow-shlib-undefined -Wl,-rpath-link,$(APK_STAGE)/lib"

	cmake --build $(MYAPP_DIR)/build --parallel $(shell nproc)
	cmake --install $(MYAPP_DIR)/build
	@touch $@

# ---------------------------------------------------------------------------
# Aggregate target
# ---------------------------------------------------------------------------
source/mycustomapps-ready:
	@mkdir -p source
	@touch $@

source/mycustomapps-built-$(QNX_ARCH): source/mycustomapps-ready source/myapp-built-$(QNX_ARCH)
	@echo "custom apps: all built."
	@touch $@

.PHONY: mycustomapps mycustomapps-clean

mycustomapps: source/mycustomapps-built-$(QNX_ARCH)

mycustomapps-clean:
	rm -f  source/mycustomapps-ready
	rm -f  source/mycustomapps-built-$(QNX_ARCH)
	rm -f  source/myapp-ready
	rm -f  source/myapp-built-$(QNX_ARCH)
	rm -rf $(MYAPP_DIR)/build \
	       $(MYAPP_DIR)/qcc-wrapper.sh \
	       $(MYAPP_DIR)/qxx-wrapper.sh

# ---------------------------------------------------------------------------
# Adding a second app is just copy-paste of the block above.
# Example skeleton (uncomment and fill in):
#
MYAPP2_DIR = $(CURDIR)/myapp2
#
# $(SOURCE_DIR)/myapp2-ready:
#     @mkdir -p $(SOURCE_DIR)
#     @touch $@
#
# $(SOURCE_DIR)/myapp2-built-$(QNX_ARCH): $(SOURCE_DIR)/myapp2-ready
#     $(call make_cxx_wrapper,$(MYAPP2_DIR),)
#     rm -rf $(MYAPP2_DIR)/build
#     cmake -B $(MYAPP2_DIR)/build -S $(MYAPP2_DIR) \
#         -DCMAKE_SYSTEM_NAME=QNX \
#         -DCMAKE_CXX_COMPILER=$(MYAPP2_DIR)/qxx-wrapper.sh \
#         -DCMAKE_INSTALL_PREFIX=$(STAGE_DIR) \
#         -DCMAKE_BUILD_TYPE=Release
#     cmake --build $(MYAPP2_DIR)/build --parallel $(shell nproc)
#     cmake --install $(MYAPP2_DIR)/build
#     @touch $@
#
# $(SOURCE_DIR)/mycustomapps-built-$(QNX_ARCH): $(SOURCE_DIR)/myapp2-built-$(QNX_ARCH)
# ---------------------------------------------------------------------------