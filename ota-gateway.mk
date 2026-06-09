# ── OTA Gateway Application ───────────────────────────────────────────────────
OTA_GW_DIR  = $(CURDIR)/ota-gateway
OTA_GW_SRCS = $(OTA_GW_DIR)/main.cpp \
              $(OTA_GW_DIR)/TcpReceiver.cpp \
              $(OTA_GW_DIR)/ImageVerifier.cpp \
              $(OTA_GW_DIR)/YoctoForwarder.cpp \
              $(OTA_GW_DIR)/StatusReporter.cpp \
              $(OTA_GW_DIR)/src-gen/v1/com/myapp/ota/OtaUpdateSomeIPDeployment.cpp \
              $(OTA_GW_DIR)/src-gen/v1/com/myapp/ota/OtaUpdateSomeIPProxy.cpp \
              $(OTA_GW_DIR)/src-gen/v1/com/myapp/ota/OtaUpdateSomeIPStubAdapter.cpp

OTA_GW_HDRS = $(OTA_GW_DIR)/TcpReceiver.hpp \
              $(OTA_GW_DIR)/ImageVerifier.hpp \
              $(OTA_GW_DIR)/YoctoForwarder.hpp \
              $(OTA_GW_DIR)/StatusReporter.hpp

source/ota-gateway-ready:
	@mkdir -p source
	touch $@

source/ota-gateway-built-$(QNX_ARCH): source/ota-gateway-ready \
                                       $(OTA_GW_SRCS) $(OTA_GW_HDRS)
	@mkdir -p $(CURDIR)/stage/usr/bin

	# Stub out Linux-only symbols not available on QNX
	echo 'int eventfd(unsigned int i, int f){ return -1; }' \
		> $(OTA_GW_DIR)/stub_eventfd.c
	qcc -Vgcc_nto$(CC_TARGET) -D_QNX_SOURCE \
		-c $(OTA_GW_DIR)/stub_eventfd.c \
		-o $(OTA_GW_DIR)/stub_eventfd.o

	q++ -Vgcc_nto$(CC_TARGET)_cxx \
		-D_QNX_SOURCE -DSA_RESTART=0 -std=c++17 \
		-D__LITTLE_ENDIAN=1234 \
		-D__BIG_ENDIAN=4321 \
		-D__BYTE_ORDER=__LITTLE_ENDIAN \
		-I$(CURDIR)/stage/usr/include \
		-I$(CURDIR)/stage/usr/include/CommonAPI-3.2 \
		-I$(OTA_GW_DIR)/src-gen \
		$(OTA_GW_SRCS) \
		$(OTA_GW_DIR)/stub_eventfd.o \
		-L$(CURDIR)/stage/usr/lib \
		-Wl,-rpath-link,$(CURDIR)/stage/usr/lib \
		-lssl -lcrypto \
		-lCommonAPI -lCommonAPI-SomeIP \
		-lvsomeip3 -lvsomeip3-sd -lvsomeip3-cfg -lvsomeip3-e2e \
		-lboost_system -lboost_thread -lboost_filesystem \
		-lboost_log -lboost_log_setup \
		-lboost_atomic -lboost_chrono -lboost_regex \
		-lsocket \
		-o $(CURDIR)/stage/usr/bin/ota-gateway

	touch $@
