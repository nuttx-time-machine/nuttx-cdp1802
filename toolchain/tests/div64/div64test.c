/* Checks arch/cosmac/src/common/cosmac_div64.c (ADR 0009) against
 * reference results computed on the host (gen_vectors.py), so that the test
 * does not need libgcc's 64-bit division.  The file under test is compiled
 * with its symbols renamed to my_*.  Validation only (mikpe libc).
 */

#include <stdio.h>

typedef unsigned long long u64;
typedef long long s64;

struct vec
{
  u64 n;
  u64 d;
  u64 uq;
  u64 ur;
  u64 sq;
  u64 sr;
  int check_signed;
};

#include "div64_vectors.h"

u64 my_udivdi3(u64 n, u64 d);
u64 my_umoddi3(u64 n, u64 d);
s64 my_divdi3(s64 a, s64 b);
s64 my_moddi3(s64 a, s64 b);

int main(void)
{
  unsigned int i;
  unsigned int n = sizeof(g_vec) / sizeof(g_vec[0]);
  unsigned int errors = 0;

  for (i = 0; i < n; i++)
    {
      const struct vec *v = &g_vec[i];

      if (my_udivdi3(v->n, v->d) != v->uq || my_umoddi3(v->n, v->d) != v->ur)
        {
          errors++;
          printf("unsigned vector %u failed\n", i);
        }

      if (v->check_signed &&
          ((u64)my_divdi3((s64)v->n, (s64)v->d) != v->sq ||
           (u64)my_moddi3((s64)v->n, (s64)v->d) != v->sr))
        {
          errors++;
          printf("signed vector %u failed\n", i);
        }
    }

  printf("div64: %u vectors, errors=%u\n", n, errors);
  return errors != 0;
}
