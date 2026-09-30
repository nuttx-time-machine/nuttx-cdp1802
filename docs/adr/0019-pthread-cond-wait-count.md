# 0019 — Common code: the condition variable wait count must be 32 bits wide

Status: Proposed (agent). This is a common-code change and needs Alan's
review.
Date: 2026-09-29
Step: step-09

## Context

ostest's cancellation test 5 hung on the CDP1802: a thread waiting in
`pthread_cond_wait()` was never woken by `pthread_cond_signal()`. The
system went idle, and `pthread_join()` waited forever. The same test passes
on the host simulator at the pinned commit, also with the port's scheduler
and mutex options.

Cause, in `libs/libc/pthread`:
- `pthread_cond_wait()` does `atomic_add(COND_WAIT_COUNT(cond), 1)`, and
  `pthread_cond_signal()` reads the count the same way.
- `COND_WAIT_COUNT(cond)` is `(FAR atomic_t *)&(cond)->wait_count`, where
  `atomic_t` is `int32_t`. But `struct pthread_cond_s` declares
  `int wait_count`.

Where `int` is 16 bits, the 32-bit atomic operations cover `wait_count`
plus the 2 bytes after it. On a big-endian CPU the `+1` goes to those 2
bytes, so `wait_count` stays 0, and memory after the structure is
corrupted. A second instance of the same bug is in
`pthread_cond_signal()` and `pthread_cond_broadcast()`: they keep the
expected value of `atomic_cmpxchg()` in an `int wcnt`. A failed exchange
writes the 32-bit current value back through `&wcnt`, and on big-endian
the high half (0) lands in the 16-bit local, so the loop ends without
posting (a lost wake-up). Fixing only the field left the test hanging; the
second cause was found by auditing every `atomic_cmpxchg()` expected-value
pointer. The NuttX atomic functions take `volatile void *`, so the
compiler cannot catch either mismatch.

An audit of the other `atomic_*` uses, and of every `atomic_cmpxchg()` /
`atomic_try_cmpxchg()` expected-value variable (all other semaphore
paths use `int32_t` locals), in `sched/`, `libs/`, `mm/`, `fs/`
and the drivers the port builds found no other mismatch: inode and file
reference counts, address-environment references and the temp-buffer
bitmap are `atomic_t`. Semaphore counts and seqcounts are 32-bit fields.
The non-`CONFIG_SPINLOCK` spinlock (`uint8_t`) compiles its operations
out.

## Decision

`include/pthread.h`: `int wait_count` → `int32_t wait_count`, and
`int32_t wcnt` in `pthread_condsignal.c` and `pthread_condbroadcast.c` (the
type `atomic_t` has). That is three lines, in one commit of their own.

## Consequences

- `pthread_cond_t` is 2 bytes larger on 16-bit-`int` targets (CDP1802,
  AVR). There is no change where `int` is 32 bits. `PTHREAD_COND_INITIALIZER`
  is unchanged.
- ostest's cancellation tests pass on the CDP1802 (journal step-09).
- On little-endian 16-bit targets (AVR) the old code happened to count
  correctly but still wrote 2 bytes past the field. That is an upstream
  report candidate (Step 11).

## How to revisit

A type-checked atomic API (`atomic_t *` parameters instead of
`volatile void *`) would catch this class of bug at compile time. That is an
upstream design discussion, not a port change.
