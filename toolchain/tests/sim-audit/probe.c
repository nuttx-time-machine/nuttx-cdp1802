/* Step 02 simulator audit: one probe per run, selected by argv[1].
 *   getc  : console GETCHAR command (0xE1)
 *   stm   : CDP1804/5/6 counter op STM (68 07)
 *   xie   : CDP1804/5/6 XIE (68 0A)
 *   dsav  : CDP1804AC DSAV (68 76)
 *   rldi  : CDP1804 RLDI (68 CN), expected to work
 *   wp    : write to .text (write protection)
 *   halt  : HALT command with status 42
 */

#include <stdio.h>
#include <string.h>

extern void sim_cmd(unsigned char cmd, unsigned char arg);
extern unsigned char sim_cmd_read(unsigned char cmd);

int main(int argc, char **argv)
{
  const char *p = argc > 1 ? argv[1] : "";

  if (!strcmp(p, "getc"))
    {
      printf("getchar -> %d\n", sim_cmd_read(0xe1));
    }
  else if (!strcmp(p, "stm"))
    {
      __asm__ volatile (".byte 0x68, 0x07");
      puts("stm executed");
    }
  else if (!strcmp(p, "xie"))
    {
      __asm__ volatile (".byte 0x68, 0x0a");
      puts("xie executed");
    }
  else if (!strcmp(p, "dsav"))
    {
      __asm__ volatile (".byte 0x68, 0x76");
      puts("dsav executed");
    }
  else if (!strcmp(p, "rldi"))
    {
      __asm__ volatile (".byte 0x68, 0xc6, 0x12, 0x34" ::: "6");
      puts("rldi executed");
    }
  else if (!strcmp(p, "wp"))
    {
      *(volatile unsigned char *)(void *)main = 0;
      puts("wrote to .text");
    }
  else if (!strcmp(p, "halt"))
    {
      sim_cmd(0x00, 42);
      puts("not reached");
    }

  return 0;
}
