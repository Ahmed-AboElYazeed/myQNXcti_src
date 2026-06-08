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
#include <screen/screen.h>
#include "screen_core.h"

const static int        num_buffers = 2;

static screen_context_t screen_context = 0;
static screen_window_t  screen_window = 0;
static screen_buffer_t  win_bufs[num_buffers] = {};

bool sc_setup(int verbose, int buffer_dim[2], size_t *buffer_size,
    uint32_t *stride, bool auto_resolution) {
  int err = 0;
  err = screen_create_context(&screen_context, SCREEN_APPLICATION_CONTEXT);
  if (err != 0) {
    perror("screen_create_context APPLICATION_CONTEXT");
    return false;
  }

  err = screen_create_window(&screen_window, screen_context);
  if (err != 0) {
    perror("screen_create_window");
    return false;
  }

  int usage = SCREEN_USAGE_READ | SCREEN_USAGE_WRITE | SCREEN_USAGE_NATIVE;
  err = screen_set_window_property_iv(screen_window, SCREEN_PROPERTY_USAGE, &usage);
  if (err != 0) {
    perror("screen_set_window_property_iv READ/WRITE");
    return false;
  }

  // Set buffer dimensions from animation dimensions
  //   Window buffers will be created with this size
  if (auto_resolution) {
    err = screen_get_window_property_iv(screen_window, SCREEN_PROPERTY_BUFFER_SIZE, buffer_dim);
    if (err != 0) {
      perror("screen_set_window_property_iv BUFFER_SIZE");
      return false;
    }
    if (verbose > 0) {
      printf("Got buffer_dim: %d, %d\n", buffer_dim[0], buffer_dim[1]);
    }
  } else {
    err = screen_set_window_property_iv(screen_window, SCREEN_PROPERTY_BUFFER_SIZE, buffer_dim);
    if (err != 0) {
      perror("screen_set_window_property_iv BUFFER_SIZE");
      return false;
    }
    if (verbose > 0) {
      printf("Set buffer_dim: %d, %d\n", buffer_dim[0], buffer_dim[1]);
    }
  }

  err = screen_create_window_buffers(screen_window, num_buffers);
  if (err != 0) {
    perror("screen_create_window_buffers");
    return false;
  }

  int zorder = INT_MAX;
  err = screen_set_window_property_iv(screen_window, SCREEN_PROPERTY_ZORDER, &zorder);
  if (err != 0) {
    perror("screen_set_window_property_iv ZORDER");
    return false;
  }
  int set_status = SCREEN_STATUS_FULLY_VISIBLE;
  err = screen_set_window_property_iv(screen_window, SCREEN_PROPERTY_STATUS, &set_status);
  if (err != 0) {
    perror("screen_set_window_property_iv STATUS");
    return false;
  }
  int transp = SCREEN_TRANSPARENCY_SOURCE;
  err = screen_set_window_property_iv(screen_window, SCREEN_PROPERTY_TRANSPARENCY, &transp);
  if (err != 0) {
    perror("screen_set_window_property_iv TRANSPARENCY");
    return false;
  }

  // Get available render buffers
  //  There will be at most num_buffers available
  err = screen_get_window_property_pv(screen_window, SCREEN_PROPERTY_RENDER_BUFFERS, (void **)&win_bufs);
  if (err != 0) {
    perror("screen_get_window_property_pv RENDER_BUFFERS");
    return false;
  }

  // Get size and stride
  int bufsize = 0;
  err = screen_get_buffer_property_iv(win_bufs[0], SCREEN_PROPERTY_SIZE, &bufsize);
  if (err != 0) {
    perror("screen_get_buffer_property_iv PROPERTY_SIZE");
    return false;
  }
  *buffer_size = bufsize;
  if (verbose > 0) {
    printf("Buffer size: %zu\n", *buffer_size);
  }

  int str = 0;
  err = screen_get_buffer_property_iv(win_bufs[0], SCREEN_PROPERTY_STRIDE, &str);
  if (err != 0) {
    perror("screen_get_buffer_property_iv PROPERTY_STRIDE");
    return false;
  }
  *stride = str;

  return true;
}

bool screen_post(uint32_t *canvas_buffer, size_t bufsize) {
  int err = 0;
  // Get available render buffers
  //  There will be at most num_buffers available
  err = screen_get_window_property_pv(screen_window, SCREEN_PROPERTY_RENDER_BUFFERS, (void **)&win_bufs);
  if (err != 0) {
    perror("screen_get_window_property_pv RENDER_BUFFERS");
    return false;
  }
  // Get buffer pointer for filling with thorvg canvas
  // We can take from win_bufs[0], since screen swaps the buffers for us
  uint32_t *wbptr;
  err = screen_get_buffer_property_pv(win_bufs[0], SCREEN_PROPERTY_POINTER, (void **)&wbptr);
  if (err != 0) {
    perror("screen_get_buffer_property_pv POINTER");
    return false;
  }

  // Fill buffer from canvas
  memcpy(wbptr, canvas_buffer, bufsize);

  // Post window for rendering
  //  - Waits until a render buffer is available, respecting swap interval
  err = screen_post_window(screen_window, win_bufs[0], 0, NULL, 0);
  if (err != 0) {
    perror("screen_post_window");
    return false;
  }
  return true;
}

void sc_clean_up() {
  screen_destroy_window(screen_window);
  screen_destroy_context(screen_context);
}
