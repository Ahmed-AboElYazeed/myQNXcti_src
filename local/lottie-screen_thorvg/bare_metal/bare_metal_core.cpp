/*
 * Copyright (c) 2025, BlackBerry Limited. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#include <cstring>
#include <cstdio>
#include <sys/mman.h>
#include "bare_metal_core.h"

static uint32_t        *frame_buffer;
static uintptr_t        paddr = 0;

bool bare_metal_setup(int verbose, int buffer_dim[2], size_t *buffer_size,
    uint32_t *stride, bool auto_resolution) {
  // Get pointer from mbox for main window graphics
  paddr = get_paddr_frame_buffer(buffer_dim[0], buffer_dim[1], buffer_size, stride);
  if (paddr == 0) {
    perror("Failed to get mbox paddr");
    return false;
  }

  // Create the main window with pointer.
  void * temp_buffer = mmap(0, *buffer_size, PROT_READ | PROT_WRITE | PROT_NOCACHE,
      MAP_SHARED | MAP_PHYS, NOFD, paddr);

  if (temp_buffer == MAP_FAILED) {
    perror("mmap");
    free_frame_buffer(paddr);
    return false;
  }
  frame_buffer = reinterpret_cast<uint32_t *>(temp_buffer);

  return true;
}

bool bare_metal_post(uint32_t *canvasbuffer, size_t bufsize) {
  // Copy drawn frame into frame_buffer
  memcpy(frame_buffer, canvasbuffer, bufsize);

  return true;
}

void bare_metal_clean_up() {
  free_frame_buffer(paddr);
}
