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

#include "frame_buffer.h"
#include <stdio.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/rpi_mbox.h>

uintptr_t
get_paddr_frame_buffer(int const window_width, int const window_height,
                   size_t * const bufsizep, unsigned * const stridep)
{
    // Connect to the mailbox resource manager.
    int const   fd = open("/dev/mailbox", O_RDWR);
    if (fd == -1) {
        perror("Failed to open mailbox");
        return 0;
    }

    // Prepare a request.
    rpi_mbox_msg_t  mbox_msg;
    rpi_mbox_init_property_msg(&mbox_msg);

    struct {
        rpi_mbox_tag_t  set_phys_size_tag;
        union {
            struct {
                uint32_t    width;
                uint32_t    height;
            } req;
            struct {
                uint32_t    width;
                uint32_t    height;
            } resp;
        }               set_phys_size_data;
        rpi_mbox_tag_t  set_virt_size_tag;
        union {
            struct {
                uint32_t    width;
                uint32_t    height;
            } req;
            struct {
                uint32_t    width;
                uint32_t    height;
            } resp;
        }               set_virt_size_data;
        rpi_mbox_tag_t  set_virt_off_tag;
        union {
            struct {
                uint32_t    x;
                uint32_t    y;
            } req;
        }               set_virt_off_data;
        rpi_mbox_tag_t  set_depth_tag;
        union {
            struct {
                uint32_t    depth;
            } req;
        }               set_depth_data;
        rpi_mbox_tag_t  alloc_tag;
        union {
            struct {
                uint32_t    align;
            } req;
            struct {
                uint32_t    paddr;
                uint32_t    size;
            } resp;
        }               alloc_data;
        rpi_mbox_tag_t  get_pitch_tag;
        union {
            struct {
                uint32_t    pitch;
            } resp;
        }               get_pitch_data;
    } tags = {
        .set_phys_size_tag.tagid = RPI_MBOX_TAG_SET_PHYS_SIZE,
        .set_phys_size_tag.length = 8,
        .set_phys_size_data.req.width = window_width,
        .set_phys_size_data.req.height = window_height,
        .set_virt_size_tag.tagid = RPI_MBOX_TAG_SET_VIRT_SIZE,
        .set_virt_size_tag.length = 8,
        .set_virt_size_data.req.width = window_width,
        .set_virt_size_data.req.height = window_height,
        .set_virt_off_tag.tagid = RPI_MBOX_TAG_SET_VIRT_OFF,
        .set_virt_off_tag.length = 8,
        .set_virt_off_data.req.x = 0,
        .set_virt_off_data.req.y = 0,
        .set_depth_tag.tagid = RPI_MBOX_TAG_SET_DEPTH,
        .set_depth_tag.length = 4,
        .set_depth_data.req.depth = 32,
        .alloc_tag.tagid = RPI_MBOX_TAG_ALLOCATE_BUFFER,
        .alloc_tag.length = 8,
        .alloc_data.req.align = 16,
        .get_pitch_tag.tagid = RPI_MBOX_TAG_GET_PITCH,
        .get_pitch_tag.length = 4
    };

    iov_t   iov[2] = {
        {
            .iov_base = &mbox_msg,
            .iov_len = sizeof(mbox_msg)
        },
        {
            .iov_base = &tags,
            .iov_len = sizeof(tags)
        }
    };

    // Send the request to the mailbox.
    if (MsgSendv(fd, &iov[0], 2, &iov[1], 1) == -1) {
        perror("Failed to query mailbox");
        close(fd);
        return 0;
    }

#if 0
    printf("Window %ux%u Physical size %ux%u virtual size %ux%u\n",
           window_width,
           window_height,
           tags.set_phys_size_data.resp.width,
           tags.set_phys_size_data.resp.height,
           tags.set_virt_size_data.resp.width,
           tags.set_virt_size_data.resp.height);
#endif

    // Parse response.
    uintptr_t const paddr = tags.alloc_data.resp.paddr & 0x3fffffffUL;
    size_t const    size = tags.alloc_data.resp.size;
    uint32_t        pitch = tags.get_pitch_data.resp.pitch;

#if 0
    printf("Frame buffer: %p (%lx) %zu %u\n", buffer, paddr, size, pitch);
#endif

    close(fd);

    *bufsizep = size;
    *stridep = pitch;
    return paddr;
}


void
free_frame_buffer(uintptr_t paddr)
{
    // Connect to the mailbox resource manager.
    int const   fd = open("/dev/mailbox", O_RDWR);
    if (fd == -1) {
        perror("Failed to open mailbox");
        return;
    }

    // Prepare a request.
    rpi_mbox_msg_t  mbox_msg;
    rpi_mbox_init_property_msg(&mbox_msg);

    struct {
        rpi_mbox_tag_t  alloc_tag;
        union {
            struct {
                uint32_t    paddr;
            } req;
        }               alloc_data;
    } tags = {
        .alloc_tag.tagid = RPI_MBOX_TAG_RELEASE_BUFFER,
        .alloc_data.req.paddr = paddr,
        .alloc_tag.length = 4
    };

    iov_t   iov[2] = {
        {
            .iov_base = &mbox_msg,
            .iov_len = sizeof(mbox_msg)
        },
        {
            .iov_base = &tags,
            .iov_len = sizeof(tags)
        }
    };

    // Send the request to the mailbox.
    if (MsgSendv(fd, &iov[0], 2, &iov[1], 1) == -1) {
        perror("Failed to query mailbox");
        close(fd);
        return;
    }

    close(fd);
}
