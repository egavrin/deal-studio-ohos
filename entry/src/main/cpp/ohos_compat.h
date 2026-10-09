/*
 * Gaps in the OpenHarmony musl libc that current llama.cpp/ggml steps into,
 * filled here so the vendored sources stay untouched. Force-included into the C
 * sources only (CMakeLists.txt), and only takes effect on musl.
 *
 * pthread_setaffinity_np: ggml-cpu pins worker threads with it on any Linux that
 * is not Android, but this libc has no such function. For the calling thread
 * it is the same as sched_setaffinity(0, ...), which is what ggml's own
 * Android branch does.
 */
#pragma once

#if defined(__MUSL__)
#include <errno.h>
#include <pthread.h>
#include <sched.h>

static inline int vera_pthread_setaffinity_np(pthread_t thread, size_t size, const cpu_set_t *set) {
    (void)thread;
    return sched_setaffinity(0, size, set) == 0 ? 0 : errno;
}
#define pthread_setaffinity_np vera_pthread_setaffinity_np
#endif
