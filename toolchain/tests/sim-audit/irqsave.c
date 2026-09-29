/* Exercise the LSIE-based irq save/restore sketch (Step 02, Q4). */

#include <stdio.h>

extern unsigned char ie_is_set(void);
extern void irq_enable(void);
extern void irq_disable(void);
extern unsigned char sketch_irq_save(void);
extern void sketch_irq_restore(unsigned char flags);

int main(void)
{
  unsigned char outer;
  unsigned char inner;
  int fail = 0;

  irq_enable();
  outer = sketch_irq_save();            /* was 1, now 0 */
  fail |= outer != 1 || ie_is_set() != 0;
  inner = sketch_irq_save();            /* nested: was 0, stays 0 */
  fail |= inner != 0 || ie_is_set() != 0;
  sketch_irq_restore(inner);            /* stays 0 */
  fail |= ie_is_set() != 0;
  sketch_irq_restore(outer);            /* back to 1 */
  fail |= ie_is_set() != 1;

  irq_disable();
  outer = sketch_irq_save();            /* was 0 */
  sketch_irq_restore(outer);
  fail |= outer != 0 || ie_is_set() != 0;

  puts(fail ? "irqsave: FAIL" : "irqsave: PASS");
  return fail;
}
