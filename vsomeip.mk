# --- vsomeip Integration (qnx_3.5.5 branch) ---
VSOMEIP_DIR = $(CURDIR)/vsomeip

source/vsomeip-ready:
	@mkdir -p source
	@if [ ! -f "$(VSOMEIP_DIR)/CMakeLists.txt" ]; then \
		rm -rf $(VSOMEIP_DIR); \
		git clone -b qnx_3.5.5 https://github.com/qnx-ports/vsomeip.git $(VSOMEIP_DIR); \
	fi
	touch $@

source/vsomeip-built-$(QNX_ARCH): source/vsomeip-ready source/boost-built-$(QNX_ARCH)
	@mkdir -p $(VSOMEIP_DIR)
	echo '#!/bin/bash' > $(VSOMEIP_DIR)/qxx-wrapper.sh
	echo 'exec q++ -Vgcc_nto$(CC_TARGET)_cxx -D_QNX_SOURCE -D_HAS_CONDITIONAL_EXPLICIT=0 -D__EXT \
		-Wp,-Uisnan -Wp,-Uisinf -Wp,-Usignbit -Wp,-Ufpclassify -Wp,-Uisfinite -Wp,-Uisnormal \
		-Wp,-Uisgreater -Wp,-Uisgreaterequal -Wp,-Uisless -Wp,-Uislessequal -Wp,-Uislessgreater -Wp,-Uisunordered \
		-DSA_RESTART=0 -std=c++17 -L$(CURDIR)/stage/usr/lib "$$@"' >> $(VSOMEIP_DIR)/qxx-wrapper.sh
	chmod +x $(VSOMEIP_DIR)/qxx-wrapper.sh
	
	echo '#!/bin/bash' > $(VSOMEIP_DIR)/qcc-wrapper.sh
	echo 'exec qcc -Vgcc_nto$(CC_TARGET) -D_QNX_SOURCE -DSA_RESTART=0 -L$(CURDIR)/stage/usr/lib "$$@"' >> $(VSOMEIP_DIR)/qcc-wrapper.sh
	chmod +x $(VSOMEIP_DIR)/qcc-wrapper.sh

	@mkdir -p $(CURDIR)/stage/usr/lib
	echo 'void dummy_rt(){}' > $(VSOMEIP_DIR)/dummy_rt.c
	$(VSOMEIP_DIR)/qcc-wrapper.sh -c -o $(VSOMEIP_DIR)/dummy_rt.o $(VSOMEIP_DIR)/dummy_rt.c
	nto$(QNX_ARCH)-ar rcs $(CURDIR)/stage/usr/lib/librt.a $(VSOMEIP_DIR)/dummy_rt.o
	rm -rf $(VSOMEIP_DIR)/build
	
	cmake -B $(VSOMEIP_DIR)/build -S $(VSOMEIP_DIR) \
		-DCMAKE_SYSTEM_NAME=QNX \
		-DCMAKE_C_COMPILER=$(VSOMEIP_DIR)/qcc-wrapper.sh \
		-DCMAKE_CXX_COMPILER=$(VSOMEIP_DIR)/qxx-wrapper.sh \
		-DCMAKE_INSTALL_PREFIX=$(CURDIR)/stage/usr \
		-DCMAKE_PREFIX_PATH=$(CURDIR)/stage/usr \
		-DBOOST_ROOT=$(CURDIR)/stage/usr \
		-DBoost_NO_SYSTEM_PATHS=ON \
		-DENABLE_SIGNAL_HANDLING=1 \
		-DPKG_CONFIG_EXECUTABLE=/bin/false \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_CXX_FLAGS="-D_HAS_CONDITIONAL_EXPLICIT=0"
	cmake --build $(VSOMEIP_DIR)/build --parallel $(shell nproc)
	cmake --install $(VSOMEIP_DIR)/build
	touch $@
