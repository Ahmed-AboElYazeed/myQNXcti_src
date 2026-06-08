# --- CommonAPI Core Runtime Snippet ---
CAPI_CORE_DIR = $(CURDIR)/capicxx-core-runtime

source/commonapi-ready:
	@mkdir -p source
	@if [ ! -d "$(CAPI_CORE_DIR)" ]; then \
		git clone https://github.com/COVESA/capicxx-core-runtime.git $(CAPI_CORE_DIR); \
	fi
	touch $@

source/commonapi-built-$(QNX_ARCH): source/commonapi-ready
	rm -f $(CAPI_CORE_DIR)/qxx-wrapper.sh $(CAPI_CORE_DIR)/qcc-wrapper.sh
	echo '#!/bin/bash' > $(CAPI_CORE_DIR)/qxx-wrapper.sh
	echo 'exec q++ -Vgcc_nto$(CC_TARGET)_cxx -D_QNX_SOURCE -DSA_RESTART=0 -std=c++17 -L$(CURDIR)/stage/usr/lib "$$@"' >> $(CAPI_CORE_DIR)/qxx-wrapper.sh
	chmod +x $(CAPI_CORE_DIR)/qxx-wrapper.sh
	echo '#!/bin/bash' > $(CAPI_CORE_DIR)/qcc-wrapper.sh
	echo 'exec qcc -Vgcc_nto$(CC_TARGET) -D_QNX_SOURCE -DSA_RESTART=0 -L$(CURDIR)/stage/usr/lib "$$@"' >> $(CAPI_CORE_DIR)/qcc-wrapper.sh
	chmod +x $(CAPI_CORE_DIR)/qcc-wrapper.sh

	cmake -B $(CAPI_CORE_DIR)/build -S $(CAPI_CORE_DIR) \
		-DCMAKE_SYSTEM_NAME=QNX \
		-DCMAKE_C_COMPILER=$(CAPI_CORE_DIR)/qcc-wrapper.sh \
		-DCMAKE_CXX_COMPILER=$(CAPI_CORE_DIR)/qxx-wrapper.sh \
		-DCMAKE_INSTALL_PREFIX=$(CURDIR)/stage/usr \
		-DCMAKE_BUILD_TYPE=Release
	
	cmake --build $(CAPI_CORE_DIR)/build --parallel $(shell nproc)
	cmake --install $(CAPI_CORE_DIR)/build
	touch $@