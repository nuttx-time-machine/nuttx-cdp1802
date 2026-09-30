/* main.c -- code-banking test (Step 06b), fixed ROM.
 *
 * Runs ROUNDS rounds of calls between fixed code and three banks (nested
 * recursion through all banks, stack arguments, function pointers, a tail
 * call) while the cycle timer interrupts every PERIOD machine cycles and
 * the interrupt routine itself calls banked code (it takes about 1 170
 * cycles, so PERIOD must be larger for the main loop to make progress).  Each result is compared
 * with the same computation done in fixed code.  Prints a summary and exits
 * with status 0 when every check passed.
 */

#include "banktest.h"

#ifndef ROUNDS
#  define ROUNDS 200
#endif

#ifndef PERIOD
#  define PERIOD 1999UL
#endif

#ifndef DEPTH
#  define DEPTH 12                  /* far calls nested by a_chain() */
#endif

static unsigned int g_errors;

static const intfn_t g_fns[] __attribute__((unused)) =
{
  a_twice, b_triple, c_neg, fixed_square
};

int fixed_square(int x)
{
  return x * x;
}

static unsigned long __attribute__((unused))
ref_chain(int n, unsigned long acc)
{
  static const int mul[3] =
  {
    3, 5, 7
  };

  static const int add[3] =
  {
    1, 2, 3
  };

  int k = 0;
  unsigned long adds = 0;

  while (n > 0)
    {
      acc = acc * mul[k] + n;
      adds += add[k];
      n--;
      k = (k + 1) % 3;
    }

  return acc + adds;
}

static void puts_(const char *s)
{
  while (*s)
    {
      putch(*s++);
    }
}

static void __attribute__((unused)) putu(unsigned long v)
{
  char buf[12];
  int i = 0;

  do
    {
      buf[i++] = '0' + v % 10;
      v /= 10;
    }
  while (v != 0);

  while (i > 0)
    {
      putch(buf[--i]);
    }
}

static void __attribute__((unused)) check(long got, long expected)
{
  if (got != expected)
    {
      g_errors++;
    }
}

void cosmac_brs_overflow(void)
{
  puts_("BRS overflow\n");
  sim_exit(3);
}

#ifdef BENCH
/* Call cost: BENCH=1 calls b_inc() (bank 1, through its stub) 1000 times,
 * BENCH=2 calls fixed_inc() (fixed ROM, near call) 1000 times; the
 * difference of the two cycle counts / 1000 is the extra cost of a far
 * call and return.
 */

int __attribute__((noinline)) fixed_inc(int x)
{
  return x + 1;
}

int main(void)
{
  int x = 0;
  unsigned int i;

  for (i = 0; i < 1000; i++)
    {
#  if BENCH == 1
      x = b_inc(x);
#  else
      x = fixed_inc(x);
#  endif
    }

  return x != 1000;
}
#else
int main(void)
{
  unsigned int round;
  unsigned int n;

  isr_bank_install();
  sim_cmd(0x81, (unsigned char)(PERIOD));        /* cycle-timer period */
  sim_cmd(0x82, (unsigned char)(PERIOD >> 8));
  sim_cmd(0x83, (unsigned char)(PERIOD >> 16));
  sim_cmd(0x13, 0x01);                            /* enable IRQ 0 */
  sim_cmd(0x80, 4);                               /* timer mode 4 */
#ifndef NO_IRQ
  irq_enable();
#endif

  for (round = 0; round < ROUNDS; round++)
    {
      int x = (int)((round * 37 + 11) & 0x7f);
      int d = (int)(round % (DEPTH + 1));
      unsigned int i;

      check(a_chain(d, round), ref_chain(d, round));
      check(a_tail(x), x + 1);
      check(a_args(x, 2, 3, 4, 5, 6, round),
            (long)(x + 1) * 4 + 6 * 8 + 10 * 12 + (long)round * 2 -
            (x + 1) + (long)x * x);
      check(b_fn(0)(x), 7L * x);                 /* static, via its stub */
      check(b_fn(1) == b_triple, 1);             /* same stub as &b_triple */
      check(a_apply(b_fn(0), x), 7L * x + (x ^ 0x5a));
      for (i = 0; i < sizeof(g_fns) / sizeof(g_fns[0]); i++)
        {
          int f = g_fns[i](x);
          check(a_apply(g_fns[i], x), f + (x ^ 0x5a));
        }
    }

  irq_disable();
  n = g_isr_hook_count;
#ifndef NO_IRQ
  if (n == 0 || g_a_leaf_count != n)
#else
  if (g_a_leaf_count != n)
#endif
    {
      g_errors++;
    }

  puts_("banking rounds=");
  putu(ROUNDS);
  puts_(" irqs=");
  putu(n);
  puts_(" errors=");
  putu(g_errors);
  putch('\n');
  return g_errors != 0;
}
#endif
