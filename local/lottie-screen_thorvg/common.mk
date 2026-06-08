ifndef QCONFIG
QCONFIG=qconfig.mk
endif
include $(QCONFIG)

define PINFO
PINFO DESCRIPTION = Sample lottie animation renderer using thorvg
endef
INSTALLDIR=usr/local/bin
NAME=lottie-player
USEFILE=

DEBUG=-g -O0

# !! BAREMETAL BACKEND IS ONLY AVAILABLE FOR THE RPi4 PLATFORM !!
# For bare-metal, rpi_mbox must be launched using direct access
# Pass as a flag to make to switch between bare-metal/mailbox backend
# and screen. e.g.:
# 	make CXXFLAGS=-DBAREMETAL
ifneq ($(findstring -DBAREMETAL,$(CXXFLAGS)),)
	ifneq (CPULIST, x86_64)
		LIBS = thorvg gomp
		EXTRA_SRCVPATH = $(PROJECT_ROOT)/bare_metal
	else
		$(CXXFLAGS) := $(filter-out -DBAREMETAL,$(CXXFLAGS))
		LIBS = screen thorvg gomp
		EXTRA_SRCVPATH = $(PROJECT_ROOT)/screen
	endif
else
	LIBS = screen thorvg gomp
	EXTRA_SRCVPATH = $(PROJECT_ROOT)/screen
endif

include $(MKFILES_ROOT)/qtargets.mk
