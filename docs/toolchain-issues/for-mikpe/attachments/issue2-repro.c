/* Toolchain issue 0002: wrong code at -Os (docs/toolchain-issues/0002-*.md).
 * bad(a, b) must return a - b; at -Os it returns a.
 */

typedef unsigned long long u64;
#define NI __attribute__((noinline))

NI u64 f(u64 v, int n) { return n ? v + 100 : v; }          /* identity for n=0 */
NI u64 g(u64 x, u64 y, u64 *p) { return p ? 0 : x - y; }   /* x - y for p=0 */

NI u64 bad(u64 a, u64 b)
{
  return f(g(f(a, 0), f(b, 0), 0), 0);                     /* must be a - b */
}
