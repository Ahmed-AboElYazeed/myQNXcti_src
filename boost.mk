# --- Boost 1.82.0 Integration (Direct Build with Wrapper & Dummy Libs) ---
BOOST_VER = 1.82.0
BOOST_DIR = $(CURDIR)/boost
BOOST_TAR = boost_1_82_0.tar.gz

ifeq ($(TARGET),qemu)
    CC_TARGET = x86_64
else
    CC_TARGET = $(QNX_ARCH)le
endif

source/boost-ready:
	@mkdir -p source
	@mkdir -p $(BOOST_DIR)
	@if [ ! -f "$(BOOST_TAR)" ]; then \
		wget -c https://archives.boost.io/release/$(BOOST_VER)/source/$(BOOST_TAR); \
	fi
	tar -xzf $(BOOST_TAR) -C $(BOOST_DIR) --strip-components=1
	touch $@

source/boost-built-$(QNX_ARCH): source/boost-ready
	cd $(BOOST_DIR) && ./bootstrap.sh
	
	echo '#!/bin/bash' > $(BOOST_DIR)/qcc-wrapper.sh
	echo 'exec q++ -Vgcc_nto$(CC_TARGET)_cxx -D_QNX_SOURCE -D_HAS_CONDITIONAL_EXPLICIT=0 -Uisnan -Uisinf -Usignbit -Uisfinite -std=c++17 "$$@"' >> $(BOOST_DIR)/qcc-wrapper.sh
	chmod +x $(BOOST_DIR)/qcc-wrapper.sh
	
	echo 'void dummy_rt(){}' > $(BOOST_DIR)/dummy_rt.cpp
	$(BOOST_DIR)/qcc-wrapper.sh -c -o $(BOOST_DIR)/dummy_rt.o $(BOOST_DIR)/dummy_rt.cpp
	nto$(QNX_ARCH)-ar rcs $(BOOST_DIR)/librt.a $(BOOST_DIR)/dummy_rt.o
	
	echo "using gcc : $(QNX_ARCH) : $(BOOST_DIR)/qcc-wrapper.sh : <archiver>nto$(QNX_ARCH)-ar <ranlib>nto$(QNX_ARCH)-ranlib <cxxflags>\"-std=c++17 -D_QNX_SOURCE\" <linkflags>\"-L$(BOOST_DIR)\" ;" > $(BOOST_DIR)/user-config.jam
	
	cd $(BOOST_DIR) && ./b2 \
		--user-config=user-config.jam \
		--prefix=$(CURDIR)/stage/usr \
		toolset=gcc-$(QNX_ARCH) \
		target-os=qnxnto \
		threadapi=pthread \
		link=shared \
		threading=multi \
		--with-system --with-thread --with-log --with-filesystem \
		install
	touch $@
