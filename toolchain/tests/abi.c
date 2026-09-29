/* Step 01: ABI probe functions.  Each one isolates one ABI question; the
 * disassembly (-Os) is quoted and annotated in docs/cdp1802/abi.md.
 * main() also checks the values at run time, so the probes are known to be
 * compiled correctly and not only inspected.
 */

#include <stdio.h>

struct pair
{
  int a;
  int b;
};

struct big
{
  long x;
  long y;
  char tag;
};

/* Q1: two 16-bit args, 16-bit return: which registers? */

int add16(int a, int b)
{
  return a + b;
}

/* Q2: 32-bit args and return (long = 4 bytes = 2 registers each?) */

long add32(long a, long b)
{
  return a + b;
}

/* Q3: more than 4 words of args: which go on the stack, and where? */

int sum6(int a, int b, int c, int d, int e, int f)
{
  return a + b + c + d + e + f;
}

/* Q4: small struct returned by value */

struct pair mkpair(int a, int b)
{
  struct pair p;

  p.a = a;
  p.b = b;
  return p;
}

/* Q5: large struct returned by value (hidden pointer?) */

struct big mkbig(long x, long y)
{
  struct big r;

  r.x = x;
  r.y = y;
  r.tag = 'B';
  return r;
}

/* Q6: callee-saved registers: force values live across a call */

extern int opaque(int v);

int keep_live(int a, int b, int c)
{
  int r = opaque(a);

  return r + a + b + c;
}

/* Q7: indirect call through a function pointer */

int call_ptr(int (*fn)(int), int v)
{
  return fn(v) + 1;
}

/* Q8: 64-bit arithmetic and char (unsigned by default?) */

long long mul64(long long a, long long b)
{
  return a * b;
}

int char_is_unsigned(void)
{
  char c = (char)0xff;

  return c > 0;
}

/* Q9: local array: frame allocation, SP-relative addressing */

int local_array(int n)
{
  volatile char buf[20];
  int i;

  for (i = 0; i < 20; i++)
    {
      buf[i] = (char)(i + n);
    }

  return buf[n % 20];
}

int opaque(int v)
{
  return v * 3;
}

int main(void)
{
  struct pair p = mkpair(3, 4);
  struct big g = mkbig(0x12345678L, -2L);
  int fail = 0;

  fail |= add16(1000, 234) != 1234;
  fail |= add32(0x10000L, 0x2345L) != 0x12345L;
  fail |= sum6(1, 2, 3, 4, 5, 6) != 21;
  fail |= p.a != 3 || p.b != 4;
  fail |= g.x != 0x12345678L || g.y != -2L || g.tag != 'B';
  fail |= keep_live(5, 6, 7) != 33;
  fail |= call_ptr(opaque, 7) != 22;
  fail |= mul64(0x100000000LL, 3) != 0x300000000LL;
  fail |= char_is_unsigned() != 1;
  fail |= local_array(5) != 10;
  printf("sizeof: short=%d int=%d long=%d llong=%d ptr=%d float=%d double=%d\n",
         (int)sizeof(short), (int)sizeof(int), (int)sizeof(long),
         (int)sizeof(long long), (int)sizeof(void *), (int)sizeof(float),
         (int)sizeof(double));
  puts(fail ? "abi: FAIL" : "abi: PASS");
  return fail;
}
