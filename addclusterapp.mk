# =============================================================================
# addclusterapp.mk — Cross-compile the Cluster Qt6 Quick app for QNX CTI
#
# Include this file from src/Makefile:
#     include addclusterapp.mk
#     all: clusterapp
#
# LESSONS APPLIED FROM CALCULATOR APP:
#
#   1. math.h macro conflict (-U flags)
#      QNX <math.h> defines isnan/isinf/isfinite as C macros.
#      Qt6 headers call std::isnan(...) which the preprocessor corrupts.
#      Fix: pass -Uisnan -Uisinf etc. via CMAKE_CXX_FLAGS so every
#      translation unit (including MOC-generated ones) gets the undefs.
#
#   2. libc++ include order (-isystem not -I)
#      Using -I for QNX system headers causes <cstddef>/<cmath> to find
#      the C stdlib header before the libc++ wrapper, breaking the build.
#      Fix: use -isystem so the compiler treats them as system headers
#      and applies the correct search priority.
#
#   3. EGL/GLES cmake probe bypass (-DHAVE_EGL=TRUE)
#      CMake tries to compile a test program to detect EGL. During cross-
#      compile the probe fails because cmake can't run aarch64 binaries.
#      Fix: set HAVE_EGL and HAVE_GLESv2 cache variables directly, and
#      provide explicit library paths so cmake skips the probe entirely.
#
#   4. Transitive linker dependencies (--allow-shlib-undefined)
#      Qt6 libs depend on xkbcommon, harfbuzz, freetype, glib etc. These
#      exist on the target (via APK) but not in the cross-linker sysroot.
#      The linker errors on missing transitive deps even though they'll
#      resolve at runtime. Fix: --allow-shlib-undefined + -rpath-link.
#
#   5. App process stopped by shell job control
#      Running in background with & causes STOPPED state if the process
#      tries to read stdin. Fix on target: nohup ... < /dev/null ... &
#      (This is a runtime concern, not a build concern — documented here
#      for reference.)
#
#   6. slog2 and socket — QNX-specific libs
#      The original CMakeLists.txt linked slog2 and socket only when
#      CMAKE_SYSTEM_NAME=QNX. We removed that from cmake and handle it
#      here via CMAKE_EXE_LINKER_FLAGS so the cmake file stays portable.
# =============================================================================


# -----------------------------------------------------------------------------
# CPU target resolution
# QNX_ARCH is set by qnxsdp-env.sh: "aarch64" for RPi5, "x86_64" for QEMU.
# CC_TARGET adds the ABI suffix expected by qcc -V flags.
# -----------------------------------------------------------------------------
ifeq ($(TARGET),qemu)
    CC_TARGET = x86_64
else
    CC_TARGET = $(QNX_ARCH)le
endif


# -----------------------------------------------------------------------------
# Paths
#
# STAGE_DIR      cmake installs the binary here. Snippet references this.
# APK_STAGE      Qt6 libs, headers, cmake configs installed by the APK system.
# HOST_MAKE      explicit make path — cmake needs this for QNX host builds.
# QNX_TARGET_DIR QNX SDP target tree: libc++, POSIX headers, system libs.
# QT_HOST_PATH   host Linux Qt6 (same minor version as APK Qt6).
#                Required for host-side tools: moc, rcc, qmlcachegen, etc.
#                These tools run on your Linux laptop, not on the target.
#
# CLUSTER_DIR    absolute path to the Cluster app source.
#                Lives outside the CTI repo — change this to your actual path.
#                The build system does not care where source lives, only
#                where the compiled output lands (STAGE_DIR).
# -----------------------------------------------------------------------------
STAGE_DIR      = $(CURDIR)/stage/nto/$(CC_TARGET)/usr
APK_STAGE      = $(CURDIR)/../apk/stage/apk_root/usr
HOST_MAKE     := $(shell which make)
QNX_TARGET_DIR = $(CURDIR)/../qnx800/target/qnx
QT_HOST_PATH  ?= /home/zee/Qt/6.10.2/gcc_64

CLUSTER_DIR    = /home/zee/ITI_Files/QT/QT_Cpp_GUIs/Cluster


# -----------------------------------------------------------------------------
# C compiler wrapper
#
# CMake expects a standard compiler executable. QNX's qcc uses -V flags to
# select the target variant. This wrapper script bridges the gap.
#
# -Vgcc_nto$(CC_TARGET)   selects QNX/GCC for aarch64le or x86_64
# -D_QNX_SOURCE           enables QNX POSIX extensions (required for slog2
#                         function signatures and socket APIs)
#
# Written into CLUSTER_DIR and recreated on every build to avoid stale paths.
# -----------------------------------------------------------------------------
define make_c_wrapper
	@rm -f $(1)/qcc-wrapper.sh
	@echo '#!/bin/bash' > $(1)/qcc-wrapper.sh
	@echo 'exec qcc -Vgcc_nto$(CC_TARGET) -D_QNX_SOURCE $(2) "$$@"' \
	    >> $(1)/qcc-wrapper.sh
	@chmod +x $(1)/qcc-wrapper.sh
endef


# -----------------------------------------------------------------------------
# C++ compiler wrapper
#
# -Vgcc_nto$(CC_TARGET)_cxx     selects the C++ variant of the QNX compiler
# -D_QNX_SOURCE                 QNX POSIX extensions
# -D_HAS_CONDITIONAL_EXPLICIT=0 suppresses a libc++ compatibility warning
#                               that fires when mixing QNX and libc++ headers
# -std=c++17                    Qt6 Quick requires C++17 internally even if
#                               your own code targets C++14
# -isystem <path>               adds headers at SYSTEM priority — lower than
#                               project headers but with correct relative order
#                               among themselves. Critical for libc++ wrappers:
#                               c++/v1 must come before the raw C headers so
#                               <cmath> finds libc++'s math.h wrapper, not the
#                               QNX C math.h directly.
# -----------------------------------------------------------------------------
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


# =============================================================================
# Cluster app build
# =============================================================================

# -----------------------------------------------------------------------------
# Stamp 1: source/clusterapp-ready
#
# Verifies the source directory exists before attempting to build.
# For a GitHub-hosted app, replace the existence check with a git clone:
#
#   git clone https://github.com/yourorg/Cluster.git $(CLUSTER_DIR)
#   cd $(CLUSTER_DIR) && git checkout <tag>
#
# Creates: src/source/clusterapp-ready (empty stamp file)
# -----------------------------------------------------------------------------
source/clusterapp-ready:
	@mkdir -p source
	@if [ ! -d "$(CLUSTER_DIR)" ]; then \
	    echo "ERROR: CLUSTER_DIR=$(CLUSTER_DIR) does not exist."; \
	    echo "       Set CLUSTER_DIR in addclusterapp.mk to your source path."; \
	    exit 1; \
	fi
	@touch $@


# -----------------------------------------------------------------------------
# Stamp 2: source/clusterapp-built-$(QNX_ARCH)
#
# The main cross-compile step. Depends on clusterapp-ready.
# Add library stamp dependencies here if Cluster depends on boost/vsomeip etc:
#     source/clusterapp-built-$(QNX_ARCH): source/clusterapp-ready \
#         source/boost-built-$(QNX_ARCH)
#
# cmake flags explained:
#
#   CMAKE_SYSTEM_NAME=QNX
#       Tells cmake this is a QNX cross-compile. Sets CMAKE_SYSTEM_NAME
#       which Qt6's cmake configs check to enable QNX-specific code paths.
#       This is what makes Qt6 enable the qnx platform plugin etc.
#
#   CMAKE_C/CXX_COMPILER
#       Points to our wrapper scripts. cmake will use these for all
#       compilation and for its internal compiler detection tests.
#
#   CMAKE_INSTALL_PREFIX=$(STAGE_DIR)
#       "cmake install" copies the binary to stage/nto/aarch64le/usr/bin/
#       The snippet then picks it up from there.
#
#   CMAKE_PREFIX_PATH
#       Where find_package(Qt6) looks for Qt6Config.cmake.
#       We list both STAGE_DIR (for any libs we built from source) and
#       APK_STAGE (for Qt6 and other APK-installed libs).
#
#   Qt6_DIR
#       Explicit override for Qt6Config.cmake location. Without this cmake
#       might find the host Qt6 instead of the cross-compiled one.
#
#   QT_HOST_PATH
#       Your host Linux Qt6 installation. Qt6's cmake toolchain uses this
#       to find moc, rcc, qmlcachegen — tools that run on Linux during the
#       build, not on the QNX target.
#
#   CMAKE_CXX_FLAGS -U...
#       Undefine QNX math.h macros AFTER they are defined by any include.
#       These flags apply to every translation unit including MOC-generated
#       files (mocs_compilation.cpp, qmlcache_loader.cpp etc.) which is
#       where the std::isnan errors originally appeared.
#       Do NOT use -include qnx_math_fix.h here — that approach broke
#       cmake's internal EGL/GLES compile probes.
#
#   CMAKE_FIND_ROOT_PATH
#       The cross-compile sysroot. find_library() and find_path() search
#       here instead of the host filesystem.
#
#   CMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
#       Never look on the host for libraries. Only look in our sysroot.
#
#   CMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
#       Never look on the host for headers.
#
#   CMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH
#       cmake config files (Qt6Config.cmake etc.) can live on the host
#       (they're architecture-independent metadata). BOTH allows cmake to
#       find them either in the sysroot or on the host.
#
#   HAVE_EGL=TRUE / HAVE_GLESv2=TRUE
#       These are the internal cache variables Qt6Gui's cmake checks.
#       Setting them directly skips the compile probe that fails during
#       cross-compilation (cmake can't run aarch64 test binaries on x86).
#
#   EGL_INCLUDE_DIR / EGL_LIBRARY / GLESv2_*
#       Explicit paths to EGL and GLES in the APK stage. The headers live
#       at include/EGL/egl.h (standard layout), so INCLUDE_DIR is include/.
#
#   CMAKE_EXE_LINKER_FLAGS
#       -L$(APK_STAGE)/lib          add APK libs to linker search path
#       -L$(STAGE_DIR)/lib          add our staged libs to search path
#       -lslog2                     QNX system logger (used in cluster.cpp)
#       -lsocket                    QNX socket library (needed by Qt network)
#       --allow-shlib-undefined     don't error on symbols that exist in Qt6
#                                   shared libs but whose dependencies
#                                   (xkbcommon, harfbuzz, freetype, glib...)
#                                   are not in our cross-linker sysroot.
#                                   They will resolve at runtime from APK.
#       -rpath-link,$(APK_STAGE)/lib  tells linker where to find transitive
#                                   dependencies for symbol resolution
#                                   without embedding the path in the binary.
#
# What this step creates on disk:
#   CLUSTER_DIR/qcc-wrapper.sh         C cross-compiler wrapper
#   CLUSTER_DIR/qxx-wrapper.sh         C++ cross-compiler wrapper
#   CLUSTER_DIR/build/                 cmake out-of-source build directory
#   CLUSTER_DIR/build/appCluster       compiled ELF binary (before install)
#   STAGE_DIR/bin/appCluster           final binary after cmake install
# -----------------------------------------------------------------------------
source/clusterapp-built-$(QNX_ARCH): source/clusterapp-ready
	$(call make_c_wrapper,$(CLUSTER_DIR),\
	    -L$(STAGE_DIR)/lib \
	    -L$(APK_STAGE)/lib)
	$(call make_cxx_wrapper,$(CLUSTER_DIR),\
	    -L$(STAGE_DIR)/lib \
	    -L$(APK_STAGE)/lib)

	rm -rf $(CLUSTER_DIR)/build

	cmake -B $(CLUSTER_DIR)/build -S $(CLUSTER_DIR) \
		-DCMAKE_SYSTEM_NAME=QNX \
		-DCMAKE_C_COMPILER=$(CLUSTER_DIR)/qcc-wrapper.sh \
		-DCMAKE_CXX_COMPILER=$(CLUSTER_DIR)/qxx-wrapper.sh \
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
		-DCMAKE_EXE_LINKER_FLAGS="-L$(APK_STAGE)/lib -L$(STAGE_DIR)/lib \
		    -lslog2 -lsocket \
		    -Wl,--allow-shlib-undefined \
		    -Wl,-rpath-link,$(APK_STAGE)/lib" \
		-DCMAKE_SHARED_LINKER_FLAGS="-L$(APK_STAGE)/lib -L$(STAGE_DIR)/lib \
		    -Wl,--allow-shlib-undefined \
		    -Wl,-rpath-link,$(APK_STAGE)/lib"

	cmake --build $(CLUSTER_DIR)/build --parallel $(shell nproc)
	cmake --install $(CLUSTER_DIR)/build

	@touch $@


# =============================================================================
# Aggregate target
#
# Add more app stamps to the dependency list as you add more apps.
# src/Makefile calls: all: clusterapp
# =============================================================================
source/clusterapp-aggregate-ready:
	@mkdir -p source
	@touch $@

source/clusterapp-aggregate-built-$(QNX_ARCH): \
        source/clusterapp-aggregate-ready \
        source/clusterapp-built-$(QNX_ARCH)
	@echo "cluster apps: all built."
	@touch $@

.PHONY: clusterapp clusterapp-clean

clusterapp: source/clusterapp-aggregate-built-$(QNX_ARCH)


# -----------------------------------------------------------------------------
# Clean target
#
# Removes stamp files so the next `make TARGET=rpi5` re-runs from scratch.
# Does NOT delete your source files.
#
# To clean only this app:
#     make TARGET=rpi5 -Csrc clusterapp-clean
# Then rebuild:
#     make TARGET=rpi5
# -----------------------------------------------------------------------------
clusterapp-clean:
	rm -f  source/clusterapp-ready
	rm -f  source/clusterapp-built-$(QNX_ARCH)
	rm -f  source/clusterapp-aggregate-ready
	rm -f  source/clusterapp-aggregate-built-$(QNX_ARCH)
	rm -rf $(CLUSTER_DIR)/build \
	       $(CLUSTER_DIR)/qcc-wrapper.sh \
	       $(CLUSTER_DIR)/qxx-wrapper.sh