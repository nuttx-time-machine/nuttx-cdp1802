/* sim1802 fork check: deterministic cycle timer (timer mode 4), cycle
 * counter readback and IDL fast-forward.  Validation only (mikpe libc).
 *
 * The output must be identical on every run: it only depends on simulated
 * machine cycles, never on host speed.
 */

#include <stdio.h>

extern void sim_cmd(unsigned char cmd, unsigned char arg);
extern unsigned char sim_cmd_read(unsigned char cmd);
extern void idle(void);
extern void irq_enable(void);
extern void isr_install(void);
extern volatile unsigned char irq_count;

#define CMD_IRQ_WRITE_ENABLED 0x13
#define CMD_TIMER_CONTROL     0x80
#define CMD_TIMER_PERIOD0     0x81
#define CMD_TIMER_PERIOD1     0x82
#define CMD_TIMER_PERIOD2     0x83
#define CMD_CYCLES_LATCH      0x84
#define CMD_CYCLES_READ0      0x85
#define TIMER_CYCLES          4

#define PERIOD                10000UL   /* machine cycles per tick */
#define TICKS                 10

static unsigned long cycles(void)
{
  unsigned long c = 0;
  int i;

  sim_cmd(CMD_CYCLES_LATCH, 0);
  for (i = 3; i >= 0; i--)
    {
      c = (c << 8) | sim_cmd_read(CMD_CYCLES_READ0 + i);
    }

  return c;
}

int main(void)
{
  unsigned long c0;
  unsigned long c1;
  unsigned long spins = 0;
  unsigned char last;
  unsigned char i;

  isr_install();
  sim_cmd(CMD_TIMER_PERIOD0, (unsigned char)PERIOD);
  sim_cmd(CMD_TIMER_PERIOD1, (unsigned char)(PERIOD >> 8));
  sim_cmd(CMD_TIMER_PERIOD2, (unsigned char)(PERIOD >> 16));
  sim_cmd(CMD_IRQ_WRITE_ENABLED, 0x01);
  sim_cmd(CMD_TIMER_CONTROL, TIMER_CYCLES);
  irq_enable();

  /* Busy phase: spins per tick must be the same on every run. */

  last = irq_count;
  while (irq_count == last)
    {
    }

  c0 = cycles();
  for (i = 0; i < TICKS; i++)
    {
      last = irq_count;
      while (irq_count == last)
        {
          spins++;
        }
    }

  c1 = cycles();
  printf("busy: %d ticks, %lu spins, %lu cycles\n", TICKS, spins, c1 - c0);

  /* Idle phase: IDL jumps straight to the next tick. */

  last = irq_count;
  c0 = cycles();
  for (i = 0; i < TICKS; i++)
    {
      idle();
    }

  c1 = cycles();
  printf("idle: %d wakeups, irq_count +%d, %lu cycles\n",
         TICKS, (unsigned char)(irq_count - last), c1 - c0);

  sim_cmd(CMD_TIMER_CONTROL, 0);
  return 0;
}
