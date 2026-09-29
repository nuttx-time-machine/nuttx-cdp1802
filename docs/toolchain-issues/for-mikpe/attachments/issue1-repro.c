int f(int n)
{
  volatile char buf[20];
  buf[n] = 1;
  return buf[0];
}
