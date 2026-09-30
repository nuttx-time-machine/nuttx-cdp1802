/* banktest.h -- code-banking test (Step 06b): functions in three banks.
 * bank_a.c -> bank 0, bank_b.c -> bank 1, bank_c.c -> bank 2 (rules.txt);
 * main.c and the assembler files stay in fixed ROM.
 */

#ifndef BANKTEST_H
#define BANKTEST_H

typedef int (*intfn_t)(int);

/* bank 0 */

unsigned long a_chain(int n, unsigned long acc);
int a_twice(int x);
int a_apply(intfn_t fn, int x);
int a_tail(int x);
long a_args(int a, int b, int c, int d, int e, int f, long g);
int a_local(int x);
void a_leaf(void);
extern volatile unsigned int g_a_leaf_count;

/* bank 1 */

unsigned long b_chain(int n, unsigned long acc);
int b_triple(int x);
int b_inc(int x);
long b_args(int a, int b, int c, int d, int e, int f, long g);
intfn_t b_fn(int i);

/* bank 2 */

unsigned long c_chain(int n, unsigned long acc);
int c_neg(int x);
void isr_hook(void);
extern volatile unsigned int g_isr_hook_count;

/* fixed */

void putch(char c);
void sim_exit(int status);
void sim_cmd(unsigned char cmd, unsigned char arg);
void irq_enable(void);
void irq_disable(void);
void isr_bank_install(void);
int fixed_square(int x);

#endif
