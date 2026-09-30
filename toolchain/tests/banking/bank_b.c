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

/* Addresses of this object's own functions (a static one and a global
 * one) in a table: the placement tool must route them through stubs, or
 * callers in other regions would jump into bank 1 without selecting it.
 */

static int b_hidden(int x)
{
  return x * 7;
}

static const intfn_t g_b_table[] =
{
  b_hidden, b_triple
};

intfn_t b_fn(int i)
{
  return g_b_table[i];
}
