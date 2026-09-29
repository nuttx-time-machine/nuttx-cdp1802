/* sim1802 fork check: console input (commands 0xE1 GETCHAR, 0xE2 STATUS).
 * Copies host stdin to stdout with each byte's case swapped, until EOF.
 * Validation only (mikpe libc).
 */

#include <stdio.h>

extern unsigned char sim_cmd_read(unsigned char cmd);

#define CMD_CONSOLE_GETCHAR 0xe1
#define CMD_CONSOLE_STATUS  0xe2

int main(void)
{
  unsigned int n = 0;
  unsigned char st;

  for (; ; )
    {
      st = sim_cmd_read(CMD_CONSOLE_STATUS);
      if (st & 1)
        {
          unsigned char c = sim_cmd_read(CMD_CONSOLE_GETCHAR);

          if (c >= 'a' && c <= 'z')
            {
              c -= 32;
            }
          else if (c >= 'A' && c <= 'Z')
            {
              c += 32;
            }

          putchar(c);
          n++;
        }
      else if (st & 2)
        {
          break;
        }
    }

  printf("[%u bytes]\n", n);
  return 0;
}
