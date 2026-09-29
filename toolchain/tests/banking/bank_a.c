/* bank_a.c -- bank 0 of the code-banking test (Step 06b) */

#include "banktest.h"

volatile unsigned int g_a_leaf_count;

/* Recursion through all three banks: a -> b -> c -> a ... */

unsigned long a_chain(int n, unsigned long acc)
{
  if (n == 0)
    {
      return acc;
    }

  return b_chain(n - 1, acc * 3 + n) + 1;
}

int a_twice(int x)
{
  return 2 * x;
}

/* Calls a function pointer: a stub of any bank, or a fixed function */

int a_apply(intfn_t fn, int x)
{
  return fn(x) + a_local(x);
}

/* Tail call ("lbr b_inc") into another bank */

int a_tail(int x)
{
  return b_inc(x);
}

/* Seven arguments: some are passed on the stack, which must survive the
 * trampoline unchanged.
 */

long a_args(int a, int b, int c, int d, int e, int f, long g)
{
  return b_args(a + 1, b + 2, c + 3, d + 4, e + 5, f + 6, g * 2) +
         fixed_square(a);
}

/* Called from a_apply in the same bank: must be a direct call */

int __attribute__((noinline)) a_local(int x)
{
  return x ^ 0x5a;
}

/* Called from the interrupt hook in bank 2 */

void a_leaf(void)
{
  g_a_leaf_count++;
}
