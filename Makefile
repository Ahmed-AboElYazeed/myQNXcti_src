#
# Copyright (c) 2025, BlackBerry Limited. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
MYDIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))

# Figure out what targets are available, and make sure one of
# them has been specified. While I'm doing that generate the
# full path to the target's configuration directory.
AVAILABLE_TARGETS := $(filter-out %/README.md,$(wildcard ../targets/*))
AVAILABLE_TARGETS += $(filter-out %/README.md,$(wildcard ../private/targets/*))
TARGET_DIR := $(MYDIR)/$(filter %/$(TARGET),$(AVAILABLE_TARGETS))
AVAILABLE_TARGETS := $(notdir $(AVAILABLE_TARGETS))
ifeq ($(filter $(AVAILABLE_TARGETS),$(TARGET)),)
  $(error TARGET is not set or invalid. Available targets are: $(AVAILABLE_TARGETS))
endif

include $(TARGET_DIR)/variables.mk

# Versions/SHAs of things to download
BASH_SHA=e1c760dfe65a770fb5cc32f8c4c75d52a1b93ee5
BUILD_FILES_SHA=f5233a9d07847a77203fd6647a4c926d6e7de028
CAIRO_SHA=0a19c554acc0340f7a362119a72dec026440f82a
MESON_VERSION=1.8.1
PATTERN_RACE_SHA=60a3f77db041dda95900ef29768cad2637a9f578
SCREENWM_SHA=48c16c8965ace7be69bf3ad235be614b6c020c6d
SIMPLE_TERMINAL_SHA=947ec5466117bed06c847c9af0a70a21062102e4
RPI_GPIO_SHA=32edae2e0e8163883c1ce90b413d4f32f506b19c
RPI_MAILBOX_SHA=dd9ed5928da2553f43350136244b38ba3857f95d
RPI_THERMAL_SHA=4ba4fdc40c683acbbdf4409dc251aed1d52cfe89
THORVG_SHA=15aafbfe621fae39156b0cbc825942ce181db011
MAELSTROM_SHA=063c388fb6e4b7365d005cd25f56844ef94aca51
MAELSTROM_VERSION=Maelstrom3

QCONF_OVERRIDE=$(MYDIR)/qconf-override.mk
STAGE_ROOT=$(MYDIR)stage/nto
STAGE_COMMON=$(STAGE_ROOT)
STAGE_TARGET=$(STAGE_ROOT)/$(QNX_ARCHDIR)
APK_STAGE_ROOT=$(MYDIR)../apk/stage/apk_root

QNXUSER_REPOS=qnxuser_repos
QNXUSER_PROJECTS=qnxuser_projects
QNXUSER_SOLUTIONS=qnxuser_solutions

.PHONY: all clean cleanup_pc_files

# add the boost and common api and someip
PKGS = thorvg lottie-screen_thorvg simple-terminal boost commonapi_someip commonapi vsomeip mycustomapps clusterapp ota-gateway

ifneq ($(filter rpi4 rpi5,$(TARGET)),)
PKGS += rpi-gpio rpi-mailbox rpi-thermal
endif
ifeq ($(TARGET),qemu)
PKGS +=
endif

REPOS = 
ifneq ($(filter rpi4 rpi5,$(TARGET)),)
REPOS +=
endif
ifeq ($(TARGET),qemu)
REPOS +=
endif

PROJECTS = simple-terminal Maelstrom python_graphviz python_numpy
ifneq ($(filter rpi4 rpi5,$(TARGET)),)
PROJECTS +=
endif
ifeq ($(TARGET),qemu)
PROJECTS +=
endif

SOLUTIONS = hello_world_c hello_world_cpp hello_world_python
ifneq ($(filter rpi4 rpi5,$(TARGET)),)
SOLUTIONS +=
endif
ifeq ($(TARGET),qemu)
SOLUTIONS +=
endif

all:    $(QNXUSER_REPOS) $(foreach p,$(REPOS),$(QNXUSER_REPOS)/$(p)) \
	$(foreach p,$(PROJECTS),$(QNXUSER_PROJECTS)/$(p)) \
	$(foreach p,$(SOLUTIONS),$(QNXUSER_SOLUTIONS)/$(p)) \
	$(foreach p,$(PKGS),source/$(p)-built-$(QNX_ARCH)) \
	cleanup_pc_files


define prepare_stage =
mkdir -p $(STAGE_ROOT)
mkdir -p $(STAGE_TARGET)
endef

include boost.mk
include commonapi_someip.mk
include commonapi.mk
include vsomeip.mk
include addcustomapps.mk
include ota-gateway.mk

define prepare_stage_apk_contents =
mkdir -p $(STAGE_ROOT)/usr
mkdir -p $(STAGE_ROOT)/usr/include
mkdir -p $(STAGE_TARGET)/usr/include
cp -r $(APK_STAGE_ROOT)/usr/include/cairo $(STAGE_ROOT)/usr/include
cp -r $(APK_STAGE_ROOT)/usr/include/pixman-1 $(STAGE_ROOT)/usr/include
cp -r $(APK_STAGE_ROOT)/usr/include/SDL2 $(STAGE_ROOT)/usr/include
cp -r $(APK_STAGE_ROOT)/usr/include/SDL2 $(STAGE_TARGET)/usr/include
rm -rf $(STAGE_ROOT)/usr/include/c++
rm -rf $(STAGE_ROOT)/usr/include/clang*
cp -r $(APK_STAGE_ROOT)/usr/lib $(STAGE_TARGET)/usr
rm -rf $(STAGE_ROOT)/usr/lib/clang
rm -rf $(STAGE_ROOT)/usr/lib/lib*c++*
cp -r $(APK_STAGE_ROOT)/usr/share $(STAGE_TARGET)/usr
rm -rf $(STAGE_ROOT)/usr/lib/apk
-cp -r $(STAGE_ROOT)/usr/share/pkgconfig/* $(STAGE_TARGET)/usr/lib/pkgconfig
find $(STAGE_TARGET) -name '*.pc' -type f -exec sed -i -e 's|\/usr|$(STAGE_TARGET)\/usr|g' {} \;
find $(STAGE_TARGET)/usr/lib/cmake/SDL2 -name '*.cmake' -type f -exec sed -i -e 's|\/usr|$(STAGE_TARGET)\/usr|g' {} \;
endef

define reset_stage_pc_files =
-cp -r $(STAGE_ROOT)/usr/share/pkgconfig/* $(STAGE_TARGET)/usr/lib/pkgconfig
find $(STAGE_ROOT) -name '*.pc' -type f -exec sed -i -e 's|$(STAGE_TARGET)\/usr|\/usr|g' {} \;
find $(STAGE_TARGET)/usr/lib/cmake/SDL2 -name '*.cmake' -type f -exec sed -i -e 's|$(STAGE_TARGET)\/usr|\/usr|g' {} \;
endef

cleanup_pc_files:
	$(reset_stage_pc_files)

source/stage-ready:
	$(prepare_stage)
	mkdir -p source
	cd source && git clone https://github.com/mesonbuild/meson.git
	cd source/meson && git checkout $(MESON_VERSION)
	touch $@

source/thorvg-ready: source/stage-ready
	mkdir -p source
	cd source/ && git clone https://github.com/thorvg/thorvg.git
	cd source/thorvg && git checkout $(THORVG_SHA)
	cd source/thorvg && git apply $(MYDIR)/patches/thorvg.patch
	touch $@
source/thorvg-built-$(QNX_ARCH): source/thorvg-ready
	mkdir -p $(STAGE_TARGET)/usr
	mkdir -p $(STAGE_ROOT)/usr/include
	cd source/thorvg && python3 $(MYDIR)/source/meson/meson.py \
		setup build-$(QNX_ARCH) \
		--cross-file $(MYDIR)/patches/meson/qnx8_$(QNX_ARCH).txt \
		-Dcpp_std=gnu++14 \
		-Dprefix=$(STAGE_TARGET)/usr
	cd source/thorvg && \
		sed -i "s/\-fopenmp/-lgomp/" build-$(QNX_ARCH)/build.ninja
	cd source/thorvg && echo "y" | \
		ninja -C build-$(QNX_ARCH) install
	touch $@

source/rpi-gpio-ready:
	mkdir -p source
	cd source && git clone https://gitlab.com/qnx/projects/rpi-gpio
	cd source/rpi-gpio && git checkout $(RPI_GPIO_SHA)
	touch $@
source/rpi-gpio-built-$(QNX_ARCH): source/rpi-gpio-ready
	cd source/rpi-gpio && \
	QCONF_OVERRIDE=$(MYDIR)/qconf-override.mk \
	QNX_ARCH=$(QNX_ARCH) \
	make hinstall
	cd source/rpi-gpio && \
	EXTRA_INCVPATH=$(STAGE_TARGET)/usr/include \
	EXTRA_LIBVPATH=$(STAGE_TARGET)/usr/lib \
	MY_STAGE=$(STAGE_ROOT) make
	cd source/rpi-gpio && \
	QCONF_OVERRIDE=$(MYDIR)/qconf-override.mk \
	QNX_ARCH=$(QNX_ARCH) \
	EXTRA_INCVPATH=$(STAGE_TARGET)/usr/include \
	EXTRA_LIBVPATH=$(STAGE_TARGET)/usr/lib \
	MY_STAGE=$(STAGE_ROOT) make install
	touch $@

source/simple-terminal-ready:
	mkdir -p source
	cd source && git clone https://gitlab.com/qnx/sample-apps/simple-terminal.git
	cd source/simple-terminal && git checkout $(SIMPLE_TERMINAL_SHA)
	touch $@
source/simple-terminal-built-$(QNX_ARCH): source/simple-terminal-ready
	$(prepare_stage_apk_contents)
	cd source/simple-terminal && \
	QCONF_OVERRIDE=$(MYDIR)/qconf-override.mk \
	QNX_ARCH=$(QNX_ARCH) \
	CPULIST=$(QNX_ARCH) \
	EXTRA_INCVPATH=$(STAGE_TARGET)/usr/include \
	EXTRA_LIBVPATH=$(STAGE_TARGET)/usr/lib \
	MY_STAGE=$(STAGE_ROOT) make -C qnx/build/nto/$(QNX_ARCH) install
	touch $@

source/rpi-thermal-ready:
	mkdir -p source
	cd source && git clone https://gitlab.com/qnx/projects/rpi-thermal.git
	cd source/rpi-thermal && git checkout $(RPI_THERMAL_SHA)
	touch $@
source/rpi-thermal-built-$(QNX_ARCH): source/rpi-mailbox-built-$(QNX_ARCH) source/rpi-thermal-ready
	cd source/rpi-thermal && \
	QCONF_OVERRIDE=$(MYDIR)/qconf-override.mk \
	QNX_ARCH=$(QNX_ARCH) \
	MY_STAGE=$(STAGE_ROOT) make
	PREFIX=/usr \
	mkdir -p $(STAGE_TARGET)/sbin
	cp source/rpi-thermal/$(QNX_ARCH)/le/rpi_thermal $(STAGE_TARGET)/sbin/rpi_thermal
	touch $@

source/rpi-mailbox-ready:
	mkdir -p source
	cd source && git clone https://gitlab.com/qnx/projects/rpi-mailbox.git
	cd source/rpi-mailbox && git checkout $(RPI_MAILBOX_SHA)
	touch $@
source/rpi-mailbox-built-$(QNX_ARCH): source/rpi-mailbox-ready
	cd source/rpi-mailbox && \
	QCONF_OVERRIDE=$(MYDIR)/qconf-override.mk \
	QNX_ARCH=$(QNX_ARCH) \
	MY_STAGE=$(STAGE_ROOT) make
	mkdir -p $(STAGE_TARGET)/sbin
	cp source/rpi-mailbox/$(QNX_ARCH)/le/rpi_mbox $(STAGE_TARGET)/sbin/rpi_mbox
	mkdir -p $(STAGE_COMMON)/usr/include
	cp -r source/rpi-mailbox/public/* $(STAGE_COMMON)/usr/include
	touch $@

source/lottie-screen_thorvg-ready:
	mkdir -p source
	cp -r $(MYDIR)/local/lottie-screen_thorvg source/
	touch $@
source/lottie-screen_thorvg-built-$(QNX_ARCH): source/lottie-screen_thorvg-ready source/thorvg-built-$(QNX_ARCH)
	mkdir -p $(STAGE_TARGET)/usr/bin
	cd source/lottie-screen_thorvg && \
		QCONF_OVERRIDE=$(MYDIR)/qconf-override.mk \
		QNX_ARCH=$(QNX_ARCH) \
	        PREFIX=/usr \
		CPULIST=$(QNX_ARCH) \
		EXTRA_INCVPATH=$(STAGE_TARGET)/usr/include \
		EXTRA_LIBVPATH=$(STAGE_TARGET)/usr/lib \
		MY_STAGE=$(STAGE_ROOT) make install
	touch $@

# # added by aboelyazeed:
# # # Awadin QNX task
# source/bash-ready:
# 	mkdir -p source
# 	cd source && git clone https://github.com/qnx-ports/bash.git
# 	cd source/bash && git checkout $(BASH_SHA)
# 	touch $@

# source/bash-built-$(QNX_ARCH): source/bash-ready source/build-files-ready
# 	QCONF_OVERRIDE=$(PWD)/qconf-override.mk
# 		CPULIST=$(QNX_ARCH) \
# 		QNX_ARCH=$(QNX_ARCH) \
# 		QNX_PROJECT_ROOT="$(PWD)/source/bash" make -C
# 	source/build-files/ports/bash install -j4
# 	touch $@


# # Bash has a build-files entry
# source/build-files-ready:
# 	mkdir -p source
# 	cd source && git clone https://github.com/qnx-ports/build-files.git
# 	cd source/build-files && git checkout $(BUILD_FILES_SHA)
# 	touch $@

# source/bash-ready:
# 	mkdir -p source
# 	cd source && git clone https://github.com/qnx-ports/bash.git
# 	cd source/bash && git checkout $(BASH_SHA)
# 	touch $@

# source/bash-built-$(QNX_ARCH): source/bash-ready source/build-files-ready
# 	QCONF_OVERRIDE=$(MYDIR)/qconf-override.mk \
# 	CPULIST=$(QNX_ARCH) \
# 	QNX_ARCH=$(QNX_ARCH) \
# 	QNX_PROJECT_ROOT="$(MYDIR)/source/bash" make -C source/build-files/ports/bash install -j4
# 	touch $@

# # Pattern Race doesn't have a build-files entry, so we build it directly here
# source/pattern-race-ready:
# 	mkdir -p source
# 	cd source && git clone https://gitlab.com/ad2lahav/pattern-race.git
# 	cd source/pattern-race && git checkout $(PATTERN_RACE_SHA)
# 	touch $@

# source/pattern-race-built-$(QNX_ARCH): source/pattern-race-ready source/simple-terminal-built-$(QNX_ARCH)
# 	mkdir -p source/pattern-race/build-$(QNX_ARCH)
# 	cd source/pattern-race/build-$(QNX_ARCH) && cmake .. \
# 		-DCMAKE_TOOLCHAIN_FILE=../qnx/$(QNX_ARCHDIR)/cmake-toolchain-qnx-$(QNX_ARCHDIR).cmake \
# 		-DSDL2_DIR=$(STAGE_TARGET)/usr/lib/cmake/SDL2 \
# 		-DCMAKE_EXE_LINKER_FLAGS="-L/home/ehab/qnxCTI/qnx800/target/qnx/$(QNX_ARCHDIR)/usr/lib \
# 		-L$(STAGE_TARGET)/usr/lib \
# 		-L$(APK_STAGE_ROOT)/usr/lib \
# 		-lfreetype -lbrotlidec -lbrotlicommon -lz -lc++"
# 	cd source/pattern-race/build-$(QNX_ARCH) && make -j4
# 	mkdir -p $(STAGE_TARGET)/usr/bin/pattern-race
# 	cp source/pattern-race/build-$(QNX_ARCH)/patrace $(STAGE_TARGET)/usr/bin/pattern-race/
# 	cp -r source/pattern-race/assets $(STAGE_TARGET)/usr/bin/pattern-race/
# 	touch $@


$(QNXUSER_REPOS):
	mkdir -p $(QNXUSER_REPOS)

$(QNXUSER_PROJECTS)/simple-terminal:
	mkdir -p $(QNXUSER_PROJECTS)
	cd $(QNXUSER_PROJECTS) && git clone https://gitlab.com/qnx/sample-apps/simple-terminal.git
	cd $(QNXUSER_PROJECTS)/simple-terminal && git checkout $(SIMPLE_TERMINAL_SHA)
	cd $(QNXUSER_PROJECTS)/simple-terminal && git apply $(MYDIR)/patches/simple-terminal.patch

$(QNXUSER_PROJECTS)/Maelstrom:
	mkdir -p $(QNXUSER_PROJECTS)
	cd $(QNXUSER_PROJECTS) && git clone https://github.com/libsdl-org/Maelstrom.git -b $(MAELSTROM_VERSION)
	cd $(QNXUSER_PROJECTS)/Maelstrom && git checkout $(MAELSTROM_SHA)
	cd $(QNXUSER_PROJECTS)/Maelstrom && git apply $(MYDIR)/patches/Maelstrom.patch

$(QNXUSER_PROJECTS)/python_graphviz:
	mkdir -p $(QNXUSER_PROJECTS)
	cp -r $(MYDIR)/local/sample_projects/python_graphviz $(QNXUSER_PROJECTS)

$(QNXUSER_PROJECTS)/python_numpy:
	mkdir -p $(QNXUSER_PROJECTS)
	cp -r $(MYDIR)/local/sample_projects/python_numpy $(QNXUSER_PROJECTS)

$(QNXUSER_SOLUTIONS)/hello_world_c: local/sample_solutions/hello_world_c/hello_world.c
	mkdir -p $(QNXUSER_SOLUTIONS)
	cp -r $(MYDIR)/local/sample_solutions/hello_world_c $(QNXUSER_SOLUTIONS)

$(QNXUSER_SOLUTIONS)/hello_world_cpp: local/sample_solutions/hello_world_cpp/hello_world.cpp
	mkdir -p $(QNXUSER_SOLUTIONS)
	cp -r $(MYDIR)/local/sample_solutions/hello_world_cpp $(QNXUSER_SOLUTIONS)

$(QNXUSER_SOLUTIONS)/hello_world_python: local/sample_solutions/hello_world_python/hello_world.py
	mkdir -p $(QNXUSER_SOLUTIONS)
	cp -r $(MYDIR)/local/sample_solutions/hello_world_python $(QNXUSER_SOLUTIONS)

subdirs:=$(subst /Makefile,,$(wildcard */[Mm]akefile)) $(subst /CMakeLists.txt,,$(wildcard */CMakeLists.txt))

clean:
	$(foreach dir,$(subdirs), rm -rf $(dir);$(NEWLINE))
	rm -rf source
	rm -rf $(STAGE_ROOT)
	rm -rf $(QNXUSER_REPOS)
	rm -rf $(QNXUSER_PROJECTS)
	rm -rf $(QNXUSER_SOLUTIONS)
