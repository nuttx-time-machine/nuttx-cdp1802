/* bank_b.c -- bank 1 of the code-banking test (Step 06b) */

#include "banktest.h"

unsigned long b_chain(int n, unsigned long acc)
{
  if (n == 0)
    {
      return acc;
    }

  return c_chain(n - 1, acc * 5 + n) + 2;
}

int b_triple(int x)
{
  return 3 * x;
}

int b_inc(int x)
{
  return x + 1;
}

long b_args(int a, int b, int c, int d, int e, int f, long g)
{
  return (long)a * b + c * d + e * f + g + c_neg(a);
}
