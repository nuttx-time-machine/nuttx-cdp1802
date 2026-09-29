/* Step 02 simulator audit: timer interrupt rate, IE readback (LSIE),
 * DIS/RET inline-byte technique and IDL.  Validation only (links mikpe's libc).
 *
 * Usage: irqtest <ticks>
 * Prints busy-loop iterations per timer tick so that simulator speed can be
 * related to the timer period.
 */

#include <stdio.h>
#include <stdlib.h>

extern void sim_cmd(unsigned char cmd, unsigned char arg);
extern unsigned char ie_is_set(void);
extern void idle(void);
extern void irq_enable(void);
extern void irq_disable(void);
extern void isr_install(void);
extern volatile unsigned char irq_count;

#define CMD_IRQ_WRITE_ENABLED 0x13
#define CMD_TIMER_CONTROL     0x80
#define TIMER_10HZ            3

int main(int argc, char **argv)
{
  unsigned char ticks = argc > 1 ? (unsigned char)strtoul(argv[1], NULL, 10) : 10;
  unsigned char last;
  unsigned long spins = 0;
  unsigned char i;

  printf("IE at entry: %d\n", ie_is_set());
  irq_disable();
  printf("IE after DIS: %d\n", ie_is_set());
  irq_enable();
  printf("IE after RET: %d\n", ie_is_set());

  isr_install();
  sim_cmd(CMD_IRQ_WRITE_ENABLED, 0x01);          /* IRQ 0 = timer */
  sim_cmd(CMD_TIMER_CONTROL, TIMER_10HZ);

  /* Busy-wait phase: count loop iterations per tick. */

  last = irq_count;
  while (irq_count == last)
    {
    }

  for (i = 0; i < ticks; i++)
    {
      last = irq_count;
      while (irq_count == last)
        {
          spins++;
        }
    }

  printf("busy: %d ticks, %lu spins, %lu spins/tick\n",
         ticks, spins, spins / ticks);

  /* Idle phase: IDL until the next interrupt, ticks times. */

  last = irq_count;
  for (i = 0; i < ticks; i++)
    {
      idle();
    }

  printf("idle: %d wakeups, irq_count advanced %d\n",
         ticks, (unsigned char)(irq_count - last));

  sim_cmd(CMD_TIMER_CONTROL, 0);
  return 0;
}
