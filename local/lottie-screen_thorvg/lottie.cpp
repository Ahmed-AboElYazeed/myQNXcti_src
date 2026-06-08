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

#include <climits>
#include <stdio.h>
#include <cstring>
#include <time.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/neutrino.h>
#include <thorvg.h>

// Switch between bare_metal backend and screen backend
//  bare_metal backend is only available for the RPi4 platform,
//  and rpi_mbox must be launched using direct access

#ifdef BAREMETAL
#include "bare_metal/bare_metal_core.h"
void(*clean_up)() = bare_metal_clean_up;
bool(*buf_post)(uint32_t *canvasbuffer, size_t bufsize) = bare_metal_post;
bool(*buf_setup)(int verbose, int buffer_dim[2], size_t *buffer_size,
    uint32_t *stride, bool auto_resolution) = bare_metal_setup;
#else
#include "screen/screen_core.h"
void(*clean_up)() = sc_clean_up;
bool(*buf_post)(uint32_t *canvasbuffer, size_t bufsize) = screen_post;
bool(*buf_setup)(int verbose, int buffer_dim[2], size_t *buffer_size,
    uint32_t *stride, bool auto_resolution) = sc_setup;
#endif // BAREMETAL

static int              verbose;
static int              pre_delay = 0;
static int              post_delay = 0;

static int              window_width = 1024;
static int              window_height = 800;
static size_t           buffer_size;
static uint32_t         stride;
static int              buffer_dim[2];
static uint64_t         tick_ns = 50000000;
static uint64_t         ticks = 0;

float                   fps = 0;
bool                    custom_fps = false;
bool                    lower_resolution = false;
bool                    higher_resolution = false;
bool                    auto_resolution = false;
uint32_t               *canvas_buffer;

static tvg::Picture    *picture;
tvg::SwCanvas          *canvas;
tvg::Animation         *animation;

static bool load_lottie(char const * const filename) {
  // Create the animation and picture objects.
  animation = tvg::Animation::gen();
  picture = animation->picture();

  // Load lottie file.
  tvg::Result res = picture->load(filename);
  switch (res) {
    case tvg::Result::Success:
      if (verbose) {
        printf("Loaded %s\n", filename);
      }
      break;

    case tvg::Result::InvalidArguments:
      printf("Failed to load %s: invalid argument\n", filename);
      return false;

    case tvg::Result::NonSupport:
      printf("Failed to load %s: not supported\n", filename);
      return false;

    default:
      printf("Failed to load %s: unknown reason\n", filename);
      return false;
  }

  if (higher_resolution || lower_resolution || auto_resolution) {
    if (higher_resolution) {
      buffer_dim[0] = 1920;
      buffer_dim[1] = 1080;
    } else if (lower_resolution) {
      buffer_dim[0] = 1280;
      buffer_dim[1] = 720;
    }

    picture->size(buffer_dim[0], buffer_dim[1]);
    if (verbose > 0) {
      printf("Picture dimesions %.2dx%.2d\n", buffer_dim[0],buffer_dim[1]);
    }
    window_width = buffer_dim[0];
    window_height = buffer_dim[1];
  } else {
    float width;
    float height;

    picture->size(&width, &height);
    if (verbose > 0) {
      printf("Picture dimesions %.2fx%.2f\n", width, height);
    }

    window_width = static_cast<int>(width);
    window_height = static_cast<int>(height);
    buffer_dim[0] = window_width;
    buffer_dim[1] = window_height;
  }

  return true;
}

static bool create_canvas() {
  tvg::Result res;
  // thorVG seems to expect the stride in pixels, not bytes.
  stride /= 4;
  if (verbose > 0) {
    printf("Stride %d\n", stride);
  }

  // Create a canvas and associate it with the window buffer.
  canvas = tvg::SwCanvas::gen();
  res = canvas->target(canvas_buffer, stride, window_width, window_height,
      tvg::ColorSpace::ARGB8888);
  switch (res) {
    case tvg::Result::Success:
      break;
    case tvg::Result::InvalidArguments:
      printf("Failed to create tvg canvas target: invalid argument\n");
      return false;
    case tvg::Result::NonSupport:
      printf("Failed to create tvg canvas target: not supported\n");
      return false;
    default:
      printf("Failed to create tvg canvas target: unknown reason\n");
      return false;
  }

  // Add the picture to the canvas.
  res = canvas->push(picture);
  switch (res) {
    case tvg::Result::Success:
      break;
    case tvg::Result::InvalidArguments:
      printf("Failed to push picture to tvg canvas target: invalid argument\n");
      return false;
    case tvg::Result::NonSupport:
      printf("Failed to push picture to tvg canvas target: not supported\n");
      return false;
    default:
      printf("Failed to push picture to tvg canvas target: unknown reason\n");
      return false;
  }

  return true;
}

bool event_loop() {
  uint64_t const start = clock_gettime_mon_ns();
  uint64_t next = start;
  uint64_t last_ticks = 0;
  int frame = 0;
  tick_ns = (1.0f/fps) * 1000000000;

  if (verbose > 0) {
    if (custom_fps) {
      printf("Duration: %f seconds\n", animation->totalFrame() / fps);
      printf("Total Frames: %f\n", animation->totalFrame());
      printf("Custom FPS: %f\n", fps);
    } else {
      printf("Duration: %f seconds\n", animation->duration());
      printf("Total Frames: %f\n", animation->totalFrame());
      printf("FPS: %f\n", animation->totalFrame() / animation->duration());
      fps = animation->totalFrame() / animation->duration();
    }
    printf("Interframe delay (ns): %lu\n", tick_ns);
  }

  for (;;) {
    animation->frame(frame);
    canvas->push(animation->picture());
    canvas->update();
    canvas->draw(true);
    canvas->sync();

    while (true) {
      // Sleep up to the next frame time.
      uint64_t timeout = tick_ns - (clock_gettime_mon_ns() - next);
      if (timeout > tick_ns) { timeout = tick_ns; }
      TimerTimeout(CLOCK_MONOTONIC, _NTO_TIMEOUT_NANOSLEEP, NULL, &timeout, NULL);

      // Determine how many ticks have elapsed since the beginning.
      // This compensates for any delays in the timer.
      ticks = (clock_gettime_mon_ns() - start) / tick_ns;
      if (ticks != last_ticks) { break; }
    }

    if (!buf_post(canvas_buffer, buffer_size)) {
      printf("Error posting drawn buffer\n");
      return false;
    }

    frame += ticks - last_ticks;
    if (frame > animation->totalFrame()) {
      break;
    }

    next += (ticks - last_ticks) * tick_ns;
    last_ticks = ticks;
  }

  return true;
}

int main(int argc, char **argv) {
  for (;;) {
    int const opt = getopt(argc, argv, "s:d:w:vLHA");
    if (opt == 'd') {
      pre_delay = strtol(optarg, NULL, 0);
    } else if (opt == 'v') {
      verbose++;
    } else if (opt == 'w') {
      post_delay = strtol(optarg, NULL, 0);
    } else if (opt == 'L') {
      lower_resolution = true;
      higher_resolution = false;
      auto_resolution = false;
    } else if (opt == 'H') {
      lower_resolution = false;
      higher_resolution = true;
      auto_resolution = false;
    } else if (opt == 'A') {
      lower_resolution = false;
      higher_resolution = false;
      auto_resolution = true;
    } else if (opt == 's') {
      custom_fps = true;
      fps = strtof(optarg, NULL);
    } else {
      break;
    }
  }

  if (optind == argc) {
    printf("usage: lottie-player [-vdwsLHA] FILENAME\n");
    printf("\n");
    printf("Options:\n");
    printf("  -v Verbose\n");
    printf("  -d Delay before playing animation (seconds)\n");
    printf("  -w Delay after playing animation (seconds)\n");
    printf("  -s Custom fps (must be less than file defined fps)\n");
    printf("  -L Force resolution to 1280x720.\n");
    printf("  -H Force resolution to 1920x1080.\n");
    printf("  -A Auto-detect resolution (only for screen backend).\n");
    return EXIT_FAILURE;
  }
  char const * const filename = argv[optind];
  tvg::Initializer::init(0);

#ifdef BAREMETAL
  // bare_metal backend cannot be used while screen is running
  if (access("/dev/screen/", F_OK) == 0) {
    printf("Screen is running. Please run this without screen running.\n");
    return EXIT_FAILURE;
  }
#endif // BAREMETAL

  if (auto_resolution) {
    if (!buf_setup(verbose, buffer_dim, &buffer_size, &stride, auto_resolution)) {
      clean_up();
      return EXIT_FAILURE;
    }
    // Load the lottie file.
    if (!load_lottie(filename)) {
      return EXIT_FAILURE;
    }
    if (!custom_fps) {
      fps = animation->totalFrame() / animation->duration();
    }
  } else {
    // Load the lottie file.
    if (!load_lottie(filename)) {
      return EXIT_FAILURE;
    }
    if (!custom_fps) {
      fps = animation->totalFrame() / animation->duration();
    }
    if (!buf_setup(verbose, buffer_dim, &buffer_size, &stride, auto_resolution)) {
      clean_up();
      return EXIT_FAILURE;
    }
  }

  try {
    canvas_buffer = new uint32_t[buffer_size];
  } catch (const std::bad_alloc&) {
    perror("new[]");
    clean_up();
    return EXIT_FAILURE;
  }

  if (!create_canvas()) {
    clean_up();
    return EXIT_FAILURE;
  }

  if (fps < 0 || fps > 60) {
    printf("FPS must be within range [1, 60]. FPS provided: %f\n", fps);
    clean_up();
    return EXIT_FAILURE;
  }

  if (verbose > 0) {
    printf("Pre Delay: %d\n", pre_delay);
  }
  sleep(pre_delay);

  bool event_ret = event_loop();
  clean_up();

  if (verbose > 0) {
    printf("Post Delay: %d\n", post_delay);
  }
  sleep(post_delay);

  if (event_ret) { return EXIT_SUCCESS; }
  else { return EXIT_FAILURE; }
}
