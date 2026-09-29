/* Step 02 simulator audit: host speed of sim1802 (instructions per second).
 * Usage: speed <n>  — runs a 16-bit add loop n times.
 */

#include <stdlib.h>

volatile unsigned int sink;

int main(int argc, char **argv)
{
  unsigned long n = argc > 1 ? strtoul(argv[1], NULL, 10) : 1000;
  volatile unsigned int acc = 0;

  while (n--)
    {
      acc += 3;
    }

  sink = acc;
  return 0;
}
