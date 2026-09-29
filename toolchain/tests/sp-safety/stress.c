/* Interrupt stress test for toolchain issue 0001 / ADR 0007.
 *
 * A standard R2-stack interrupt routine (isr_r2.S) fires every PERIOD
 * machine cycles while functions with 20-byte, 300-byte and variable-size
 * frames fill and re-check their frames around nested calls.  The stack is
 * shifted by 0..255 bytes between rounds, so frame allocations cross 256-byte
 * page boundaries (the case where a two-step SP update can be torn) at many
 * different interrupt positions.  If an interrupt ever finds R2 above the
 * live stack top, its pushes corrupt a live frame and a check fails.
 *
 * Usage: stress <period-cycles> <rounds>        (validation only, mikpe libc)
 */

#include <stdio.h>
#include <stdlib.h>

extern void sim_cmd(unsigned char cmd, unsigned char arg);
extern void irq_enable(void);
extern void irq_disable(void);
extern void isr_r2_install(void);
extern volatile unsigned long isr_r2_count;

static unsigned int errors;

static void __attribute__((noinline))
fill(volatile unsigned char *p, unsigned int n, unsigned char seed)
{
  unsigned int i;

  for (i = 0; i < n; i++)
    {
      p[i] = (unsigned char)(seed + i);
    }
}

static void __attribute__((noinline))
check(volatile unsigned char *p, unsigned int n, unsigned char seed)
{
  unsigned int i;

  for (i = 0; i < n; i++)
    {
      if (p[i] != (unsigned char)(seed + i))
        {
          errors++;
        }
    }
}

static unsigned char __attribute__((noinline)) leaf20(unsigned char seed)
{
  volatile unsigned char b[20];

  fill(b, sizeof(b), seed);
  check(b, sizeof(b), seed);
  return b[seed % sizeof(b)];
}

static unsigned char __attribute__((noinline))
vla(unsigned char seed, unsigned int n)
{
  volatile unsigned char b[n];
  unsigned char r;

  fill(b, n, seed);
  r = leaf20(seed + 3);
  check(b, n, seed);
  return r;
}

static unsigned char __attribute__((noinline)) mid300(unsigned char seed)
{
  volatile unsigned char b[300];
  unsigned char r;

  fill(b, sizeof(b), seed);
  r = leaf20(seed + 1);
  r += vla(seed + 2, 40 + (seed & 31));
  check(b, sizeof(b), seed);
  return r;
}

/* Shift the stack by 1 + (round & 255) bytes before the real work. */

static unsigned char __attribute__((noinline)) shifted(unsigned int round)
{
  volatile unsigned char pad[1 + (round & 255)];
  unsigned char r;

  fill(pad, sizeof(pad), (unsigned char)round);
  r = mid300((unsigned char)round);
  check(pad, sizeof(pad), (unsigned char)round);
  return r;
}

int main(int argc, char **argv)
{
  unsigned long period = argc > 1 ? strtoul(argv[1], NULL, 0) : 211;
  unsigned int rounds = argc > 2 ? (unsigned int)strtoul(argv[2], NULL, 0) : 256;
  volatile unsigned char top[32];
  unsigned int round;
  unsigned long n;

  fill(top, sizeof(top), 0x5a);

  isr_r2_install();
  sim_cmd(0x81, (unsigned char)period);           /* cycle-timer period */
  sim_cmd(0x82, (unsigned char)(period >> 8));
  sim_cmd(0x83, (unsigned char)(period >> 16));
  sim_cmd(0x13, 0x01);                            /* enable IRQ 0 */
  sim_cmd(0x80, 4);                               /* timer mode 4 */
  irq_enable();

  for (round = 0; round < rounds; round++)
    {
      shifted(round);
    }

  irq_disable();
  n = isr_r2_count;
  check(top, sizeof(top), 0x5a);
  printf("period=%lu rounds=%u irqs=%lu errors=%u\n", period, rounds, n, errors);
  return errors != 0;
}
