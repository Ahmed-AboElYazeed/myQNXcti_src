# --- CommonAPI SOME/IP Runtime Snippet ---
CAPI_SOMEIP_DIR = $(CURDIR)/capicxx-someip-runtime

source/commonapi_someip-ready:
	@mkdir -p source
	@if [ ! -d "$(CAPI_SOMEIP_DIR)" ]; then \
		git clone https://github.com/COVESA/capicxx-someip-runtime.git $(CAPI_SOMEIP_DIR); \
	fi
	touch $@

source/commonapi_someip-built-$(QNX_ARCH): source/commonapi_someip-ready source/commonapi-built-$(QNX_ARCH) source/vsomeip-built-$(QNX_ARCH)
	rm -f $(CAPI_SOMEIP_DIR)/qxx-wrapper.sh $(CAPI_SOMEIP_DIR)/qcc-wrapper.sh
	rm -rf $(CAPI_SOMEIP_DIR)/build
	
	echo '#!/bin/bash' > $(CAPI_SOMEIP_DIR)/qxx-wrapper.sh
	echo 'exec q++ -Vgcc_nto$(CC_TARGET)_cxx -D_QNX_SOURCE -DSA_RESTART=0 -std=c++17 \
		-L$(CURDIR)/stage/usr/lib \
		-D__LITTLE_ENDIAN=1234 -D__BIG_ENDIAN=4321 -D__BYTE_ORDER=1234 \
		-DLITTLE_ENDIAN=1234 -DBIG_ENDIAN=4321 -DBYTE_ORDER=1234 \
		-Wno-narrowing "$$@"' >> $(CAPI_SOMEIP_DIR)/qxx-wrapper.sh
	chmod +x $(CAPI_SOMEIP_DIR)/qxx-wrapper.sh
	
	echo '#!/bin/bash' > $(CAPI_SOMEIP_DIR)/qcc-wrapper.sh
	echo 'exec qcc -Vgcc_nto$(CC_TARGET) -D_QNX_SOURCE -DSA_RESTART=0 -L$(CURDIR)/stage/usr/lib \
		-D__LITTLE_ENDIAN=1234 -D__BIG_ENDIAN=4321 -D__BYTE_ORDER=1234 \
		-DLITTLE_ENDIAN=1234 -DBIG_ENDIAN=4321 -DBYTE_ORDER=1234 \
		-Wno-narrowing "$$@"' >> $(CAPI_SOMEIP_DIR)/qcc-wrapper.sh
	chmod +x $(CAPI_SOMEIP_DIR)/qcc-wrapper.sh

	cmake -B $(CAPI_SOMEIP_DIR)/build -S $(CAPI_SOMEIP_DIR) \
		-DCMAKE_SYSTEM_NAME=QNX \
		-DCMAKE_C_COMPILER=$(CAPI_SOMEIP_DIR)/qcc-wrapper.sh \
		-DCMAKE_CXX_COMPILER=$(CAPI_SOMEIP_DIR)/qxx-wrapper.sh \
		-DCMAKE_INSTALL_PREFIX=$(CURDIR)/stage/usr \
		-DCMAKE_PREFIX_PATH=$(CURDIR)/stage/usr \
		-DUSE_INSTALLED_COMMONAPI=ON \
		-DCMAKE_BUILD_TYPE=Release
		
	cmake --build $(CAPI_SOMEIP_DIR)/build --parallel $(shell nproc)
	cmake --install $(CAPI_SOMEIP_DIR)/build
	touch $@