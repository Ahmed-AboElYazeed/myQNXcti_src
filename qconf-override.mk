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

-include $(MKFILES_ROOT)/qconf-override-system.mk
 
BUILD_ROOT := $(shell dirname $(QCONF_OVERRIDE))
 
INSTALL_ROOT := $(BUILD_ROOT)/stage/nto
USE_INSTALL_ROOT := 1
 
INSTALL_ROOT_nto := $(INSTALL_ROOT)
INSTALL_ROOT_darwin := $(INSTALL_ROOT)/host/darwin
INSTALL_ROOT_linux := $(INSTALL_ROOT)/host/linux
INSTALL_ROOT_win64 := $(INSTALL_ROOT)/host/win64
