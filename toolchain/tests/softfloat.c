/* Step 01: soft-float check.  mikpe's libc printf has no %f support, so the
 * results are scaled and printed as integers.  volatile defeats constant
 * folding so that the libgcc soft-fp routines really run in the simulator.
 */

#include <stdio.h>

volatile float fa = 1.5f;
volatile float fb = 2.25f;
volatile double da = 3.14159265358979;
volatile double db = 7.0;
volatile long la = 100000L;

int main(void)
{
  float f = fa * fb;              /* 3.375      -> __mulsf3 */
  double d = da * db / 2.0;       /* 10.9955... -> __muldf3, __divdf3 */
  double e = (double)la + 0.5;    /* 100000.5   -> __floatsidf, __adddf3 */
  int fail = 0;

  printf("f*1000   = %ld\n", (long)(f * 1000.0f));
  printf("d*10000  = %ld\n", (long)(d * 10000.0));
  printf("e*2      = %ld\n", (long)(e * 2.0));
  printf("f<d      = %d\n", f < d);

  fail |= (long)(f * 1000.0f) != 3375L;
  fail |= (long)(d * 10000.0) != 109955L;
  fail |= (long)(e * 2.0) != 200001L;
  fail |= !(f < d);

  puts(fail ? "softfloat: FAIL" : "softfloat: PASS");
  return fail;
}
