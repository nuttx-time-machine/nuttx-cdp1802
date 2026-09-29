/* bank_c.c -- bank 2 of the code-banking test (Step 06b) */

#include "banktest.h"

volatile unsigned int g_isr_hook_count;

unsigned long c_chain(int n, unsigned long acc)
{
  if (n == 0)
    {
      return acc;
    }

  return a_chain(n - 1, acc * 7 + n) + 3;
}

int c_neg(int x)
{
  return -x;
}

/* Called by the interrupt routine, from whatever bank was selected; makes
 * one more far call itself.
 */

void isr_hook(void)
{
  g_isr_hook_count++;
  a_leaf();
}
