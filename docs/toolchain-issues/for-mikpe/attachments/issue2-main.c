#include <stdio.h>
typedef unsigned long long u64;
u64 bad(u64 a, u64 b);
int main(void)
{
  u64 r = bad(7, 2);
  printf("bad(7, 2) = %lx:%lx, expected 0:5 -> %s\n",
         (unsigned long)(r >> 32), (unsigned long)r, r == 5 ? "OK" : "WRONG");
  return r != 5;
}
