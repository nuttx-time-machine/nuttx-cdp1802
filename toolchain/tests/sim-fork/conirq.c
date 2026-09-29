/* sim1802 fork check: interrupt-driven console input (IRQ 6).
 * Sleeps in IDL until IRQ 6, drains the input queue, then re-enables IRQ 6.
 * The console IRQ is level-like (raised again while input is queued), so the
 * generic test ISR must NOT re-enable it (irq_mask = 0): the main loop does,
 * after draining, as a deferred-processing driver would.  Stops at end of
 * input, which the simulator signals with one more IRQ 6.
 * Validation only (mikpe libc).
 */

#include <stdio.h>

extern void sim_cmd(unsigned char cmd, unsigned char arg);
extern unsigned char sim_cmd_read(unsigned char cmd);
extern void idle(void);
extern void irq_enable(void);
extern void isr_install(void);
extern volatile unsigned char irq_count;
extern volatile unsigned char irq_mask;

#define CMD_IRQ_WRITE_ENABLED 0x13
#define CMD_CONSOLE_GETCHAR   0xe1
#define CMD_CONSOLE_STATUS    0xe2
#define IRQ_CONSOLE_MASK      0x40

int main(void)
{
  unsigned int n = 0;
  unsigned char st;

  isr_install();
  irq_mask = 0;
  irq_enable();

  for (; ; )
    {
      sim_cmd(CMD_IRQ_WRITE_ENABLED, IRQ_CONSOLE_MASK);
      idle();                             /* sleep until IRQ 6 */
      while ((st = sim_cmd_read(CMD_CONSOLE_STATUS)) & 1)
        {
          putchar(sim_cmd_read(CMD_CONSOLE_GETCHAR));
          n++;
        }

      if (st & 2)
        {
          break;
        }
    }

  printf("[%u bytes, %s]\n", n, irq_count > 0 ? "irq" : "no irq");
  return 0;
}
