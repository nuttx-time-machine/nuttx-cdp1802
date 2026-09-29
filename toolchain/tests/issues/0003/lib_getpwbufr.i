# 0 "pwd/lib_getpwbufr.c"
# 0 "<built-in>"
# 0 "<command-line>"
# 1 "pwd/lib_getpwbufr.c"
# 27 "pwd/lib_getpwbufr.c"
# 1 "../../include/nuttx/config.h" 1 3 4
# 28 "pwd/lib_getpwbufr.c" 2

# 1 "../../include/stdlib.h" 1 3 4
# 31 "../../include/stdlib.h" 3 4
# 1 "../../include/nuttx/compiler.h" 1 3 4
# 32 "../../include/stdlib.h" 2 3 4

# 1 "../../include/sys/types.h" 1 3 4
# 34 "../../include/sys/types.h" 3 4
# 1 "../../include/stdint.h" 1 3 4
# 36 "../../include/stdint.h" 3 4
# 1 "../../include/arch/types.h" 1 3 4
# 58 "../../include/arch/types.h" 3 4

# 58 "../../include/arch/types.h" 3 4
typedef signed char _int8_t;
typedef unsigned char _uint8_t;

typedef signed int _int16_t;
typedef unsigned int _uint16_t;

typedef signed long _int32_t;
typedef unsigned long _uint32_t;

typedef signed long long _int64_t;
typedef unsigned long long _uint64_t;


typedef _int64_t _intmax_t;
typedef _uint64_t _uintmax_t;


typedef long unsigned int _wchar_t;





typedef unsigned int _wint_t;




typedef int _wctype_t;







typedef signed int _ssize_t;

typedef unsigned int _size_t;







typedef signed int _int_farptr_t;
typedef unsigned int _uint_farptr_t;





typedef unsigned char irqstate_t;
# 37 "../../include/stdint.h" 2 3 4
# 1 "../../include/arch/inttypes.h" 1 3 4
# 38 "../../include/stdint.h" 2 3 4
# 1 "../../include/limits.h" 1 3 4
# 34 "../../include/limits.h" 3 4
# 1 "../../include/arch/limits.h" 1 3 4
# 35 "../../include/limits.h" 2 3 4
# 39 "../../include/stdint.h" 2 3 4
# 169 "../../include/stdint.h" 3 4
typedef _int8_t int8_t;
typedef _uint8_t uint8_t;

typedef _int16_t int16_t;
typedef _uint16_t uint16_t;






typedef _int32_t int32_t;
typedef _uint32_t uint32_t;


typedef _int64_t int64_t;
typedef _uint64_t uint64_t;




typedef _int8_t int_least8_t;
typedef _uint8_t uint_least8_t;

typedef _int16_t int_least16_t;
typedef _uint16_t uint_least16_t;





typedef _int32_t int_least24_t;
typedef _uint32_t uint_least24_t;


typedef _int32_t int_least32_t;
typedef _uint32_t uint_least32_t;


typedef _int64_t int_least64_t;
typedef _uint64_t uint_least64_t;




typedef _int8_t int_fast8_t;
typedef _uint8_t uint_fast8_t;

typedef int int_fast16_t;
typedef unsigned int uint_fast16_t;





typedef _int32_t int_fast24_t;
typedef _uint32_t uint_fast24_t;


typedef _int32_t int_fast32_t;
typedef _uint32_t uint_fast32_t;


typedef _int64_t int_fast64_t;
typedef _uint64_t uint_fast64_t;
# 242 "../../include/stdint.h" 3 4
typedef _ssize_t intptr_t;
typedef _size_t uintptr_t;
# 256 "../../include/stdint.h" 3 4
typedef _intmax_t intmax_t;
typedef _uintmax_t uintmax_t;
# 35 "../../include/sys/types.h" 2 3 4
# 110 "../../include/sys/types.h" 3 4
typedef unsigned int mode_t;
# 122 "../../include/sys/types.h" 3 4
typedef uint16_t size_t;
typedef int16_t ssize_t;
typedef uint16_t rsize_t;
# 138 "../../include/sys/types.h" 3 4
typedef unsigned int uid_t;
typedef unsigned int gid_t;



typedef uint32_t dev_t;



typedef uint32_t ino_t;



typedef uint16_t nlink_t;





typedef int pid_t;





typedef int id_t;






typedef int32_t key_t;



typedef intptr_t ptrdiff_t;
# 183 "../../include/sys/types.h" 3 4
typedef _wchar_t wchar_t;






typedef _wint_t wint_t;






typedef _wctype_t wctype_t;
# 211 "../../include/sys/types.h" 3 4
typedef uint32_t fsblkcnt_t;
typedef uint32_t fsfilcnt_t;
# 223 "../../include/sys/types.h" 3 4
typedef uint32_t blkcnt_t;
typedef int32_t off_t;
typedef int32_t fpos_t;


typedef off_t loff_t;



typedef int32_t blksize_t;



typedef unsigned int socklen_t;

typedef uint16_t sa_family_t;
# 248 "../../include/sys/types.h" 3 4
typedef int64_t clock_t;
typedef int64_t time_t;
typedef int clockid_t;
typedef void *timer_t;







typedef uint32_t useconds_t;
typedef int32_t suseconds_t;




typedef volatile uint32_t cpu_set_t;






typedef unsigned char u_char;
typedef unsigned short u_short;
typedef unsigned int u_int;
typedef unsigned long u_long;



typedef unsigned char unchar;
typedef unsigned short ushort;
typedef unsigned int uint;
typedef unsigned long ulong;
typedef signed char s_char;
typedef char *caddr_t;



typedef uint8_t u_int8_t;
typedef uint16_t u_int16_t;
typedef uint32_t u_int32_t;




typedef uint64_t u_int64_t;


struct fsid_s
{
  int val[2];
};



typedef int (*main_t)(int argc, char *argv[]);







enum
{
  ERROR = -1,
  OK = 0
};


struct pthread_attr_s;
typedef struct pthread_attr_s pthread_attr_t;




struct pthread_cond_s;
typedef struct pthread_cond_s pthread_cond_t;




typedef struct pthread_condattr_s pthread_condattr_t;




typedef int pthread_key_t;




struct pthread_mutex_s;
typedef struct pthread_mutex_s pthread_mutex_t;




struct pthread_mutexattr_s;
typedef struct pthread_mutexattr_s pthread_mutexattr_t;




typedef pid_t pthread_t;




struct pthread_once_s;
typedef struct pthread_once_s pthread_once_t;
# 379 "../../include/sys/types.h" 3 4
int hello_main(int argc, char *argv[]);
# 34 "../../include/stdlib.h" 2 3 4
# 107 "../../include/stdlib.h" 3 4
struct div_s
{
  int quot;
  int rem;
};

typedef struct div_s div_t;



struct ldiv_s
{
  long quot;
  long rem;
};

typedef struct ldiv_s ldiv_t;



struct lldiv_s
{
  long long quot;
  long long rem;
};

typedef struct lldiv_s lldiv_t;
# 151 "../../include/stdlib.h" 3 4
void srand(unsigned int seed);
int rand(void);
int rand_r( unsigned int *seedp);
void lcong48( unsigned short int param[7]);
 unsigned short int *seed48( unsigned short int seed16v[3]);
void srand48(long int seedval);
long int jrand48( unsigned short int xsubi[3]);
long int lrand48(void);
long int mrand48(void);
long int nrand48( unsigned short int xsubi[3]);

double drand48(void);
double erand48( unsigned short int xsubi[3]);



long random(void);

void arc4random_buf( void *bytes, size_t nbytes);
uint32_t arc4random(void);



 char **get_environ_ptr(void);
 char *getenv( const char *name);
 char *secure_getenv( const char *name);
int putenv( const char *string);
int clearenv(void);
int setenv( const char *name, const char *value, int overwrite);
int unsetenv( const char *name);



void exit(int status) __attribute__((noreturn));
void quick_exit(int status) __attribute__((noreturn));
void abort(void) __attribute__((noreturn));
int atexit( void (*func)(void));
int at_quick_exit( void (*func)(void));
int on_exit( void (*func)(int, void *), void *arg);



void _Exit(int status) __attribute__((noreturn));
# 202 "../../include/stdlib.h" 3 4
int system( const char *cmd);


 char *realpath( const char *path, char *resolved);



long strtol( const char *nptr, char **endptr, int base);
unsigned long strtoul( const char *nptr, char **endptr, int base);
long long strtoll( const char *nptr, char **endptr, int base);
unsigned long long strtoull( const char *nptr, char **endptr,
                            int base);
float strtof( const char *str, char **endptr);

double strtod( const char *str, char **endptr);


long double strtold( const char *str, char **endptr);


int atoi( const char *nptr);
long atol( const char *nptr);
long long atoll( const char *nptr);

double atof( const char *nptr);




 char *itoa(int val, char *str, int base);



int mblen( const char *s, size_t n);
int mbtowc( wchar_t *pwc, const char *s, size_t n);
size_t mbstowcs( wchar_t *dst, const char *src, size_t len);
int wctomb( char *s, wchar_t wchar);
size_t wcstombs( char *dst, const wchar_t *src, size_t len);



 void *malloc(size_t) __attribute__((__malloc__(__builtin_free, 1))) __attribute__((__alloc_size__(1)));
 void *valloc(size_t) __attribute__((__malloc__(__builtin_free, 1))) __attribute__((__alloc_size__(1)));
void free( void *);
 void *realloc( void *, size_t) __attribute__((__alloc_size__(2)));
 void *reallocarray( void *, size_t, size_t) __attribute__((__alloc_size__(2, 3)));
 void *memalign(size_t, size_t) __attribute__((__malloc__(__builtin_free, 1))) __attribute__((__alloc_size__(2)));
 void *zalloc(size_t) __attribute__((__malloc__(__builtin_free, 1))) __attribute__((__alloc_size__(1)));
 void *calloc(size_t, size_t) __attribute__((__malloc__(__builtin_free, 1))) __attribute__((__alloc_size__(1, 2)));
 void *aligned_alloc(size_t, size_t) __attribute__((__malloc__(__builtin_free, 1))) __attribute__((__alloc_size__(2)));
int posix_memalign( void **, size_t, size_t);
# 269 "../../include/stdlib.h" 3 4
int abs(int j);
long int labs(long int j);
long long int llabs(long long int j);

div_t div(int number, int denom);
ldiv_t ldiv(long number, long denom);
lldiv_t lldiv(long long number, long long denom);



 char *mktemp( char *path_template);
int mkstemp( char *path_template);
 char *mkdtemp( char *path_template);



void qsort( void *base, size_t nel, size_t width,
                int (*compar)( const void *, const void *));



 void *bsearch( const void *key, const void *base, size_t nel,
                   size_t width, int (*compar)( const void *,
                   const void *));



 const char *getprogname(void);



int __cxa_atexit( void (*func)( void *), void *arg,
                 void *dso_handle);
# 30 "pwd/lib_getpwbufr.c" 2
# 1 "../../include/string.h" 1 3 4
# 33 "../../include/string.h" 3 4
# 1 "../../include/stddef.h" 1 3 4
# 73 "../../include/stddef.h" 3 4
typedef struct
{
  long long max_align_i;

  long double max_align_f;





} max_align_t;
# 34 "../../include/string.h" 2 3 4
# 1 "../../include/alloca.h" 1 3 4
# 35 "../../include/string.h" 2 3 4
# 66 "../../include/string.h" 3 4
 char *strdup( const char *s) __attribute__((__malloc__(__builtin_free, 1)));
 char *strndup( const char *s, size_t size) __attribute__((__malloc__(__builtin_free, 1)));
 char *strerror(int);
int strerror_r(int, char *, size_t);
size_t strlen( const char *);
size_t strnlen( const char *, size_t);
 char *strcat( char *, const char *);
size_t strlcat( char *, const char *, size_t);
 char *strncat( char *, const char *, size_t);
int strcmp( const char *, const char *);
int strncmp( const char *, const char *, size_t);
int strcoll( const char *, const char *s2);
 char *strcpy( char *dest, const char *src);
 char *stpcpy( char *dest, const char *src);
size_t strlcpy( char *dst, const char *src, size_t size);
 char *strncpy( char *, const char *, size_t);
 char *stpncpy( char *, const char *, size_t);
 char *strpbrk( const char *, const char *);
 char *strchr( const char *s, int c);
 char *strchrnul( const char *s, int c);
 char *strrchr( const char *s, int c);
size_t strspn( const char *, const char *);
size_t strcspn( const char *, const char *);
 char *strstr( const char *, const char *);
 char *strcasestr( const char *, const char *);
 char *strsep( char **, const char *);
 char *strsignal(int signum);
 char *strtok( char *, const char *);
 char *strtok_r( char *, const char *, char **);
size_t strxfrm( char *, const char *, size_t n);
int strverscmp( const char *s1, const char *s2);

 void *memchr( const void *s, int c, size_t n);
 void *memrchr( const void *s, int c, size_t n);
 void *rawmemchr( const void *s, int c);
 void *memccpy( void *s1, const void *s2, int c, size_t n);
int memcmp( const void *s1, const void *s2, size_t n);
 void *memcpy( void *dest, const void *src, size_t n) __attribute__((used));
 void *mempcpy( void *dest, const void *src, size_t n);
 void *memmove( void *dest, const void *src, size_t count);
 void *memset( void *s, int c, size_t n) __attribute__((used));
 void *memmem( const void *haystack, size_t haystacklen,
                  const void *needle, size_t needlelen);

void explicit_bzero( void *s, size_t n);
int timingsafe_bcmp( const void *b1, const void *b2, size_t n);






 char *nx_strdup( const char *s) __attribute__((__malloc__(__builtin_free, 1)));
 char *nx_strndup( const char *s, size_t size) __attribute__((__malloc__(__builtin_free, 1)));
# 31 "pwd/lib_getpwbufr.c" 2
# 1 "../../include/errno.h" 1 3 4
# 33 "../../include/errno.h" 3 4
# 1 "../../include/nuttx/irq.h" 1 3 4
# 34 "../../include/nuttx/irq.h" 3 4
# 1 "../../include/stdbool.h" 1 3 4
# 35 "../../include/nuttx/irq.h" 2 3 4




# 1 "../../include/arch/irq.h" 1 3 4
# 81 "../../include/arch/irq.h" 3 4
struct xcptcontext
{


  uint8_t regs[((4 + 2 * ((15) - 1)) + 2)];
};
# 108 "../../include/arch/irq.h" 3 4
extern volatile uint8_t *g_current_regs;
# 118 "../../include/arch/irq.h" 3 4
irqstate_t up_irq_save(void);
void up_irq_restore(irqstate_t flags);
void up_irq_enable(void);





static __attribute__((always_inline)) inline uint8_t *up_current_regs(void)
{
  return ( uint8_t *)g_current_regs;
}

static __attribute__((always_inline)) inline void up_set_current_regs( uint8_t *regs)
{
  g_current_regs = regs;
}







static __attribute__((always_inline)) inline uint16_t up_getsp(void)
{
  uint16_t sp;

  __asm__ __volatile__
    (
      "ghi 2\n\t"
      "phi %0\n\t"
      "glo 2\n\t"
      "plo %0"
      : "=r" (sp)
    );

  return sp;
}
# 40 "../../include/nuttx/irq.h" 2 3 4
# 179 "../../include/nuttx/irq.h" 3 4
typedef uint8_t irq_t;
# 202 "../../include/nuttx/irq.h" 3 4
typedef int (*xcpt_t)(int irq, void *context, void *arg);
# 252 "../../include/nuttx/irq.h" 3 4
int irq_attach(int irq, xcpt_t isr, void *arg);
# 277 "../../include/nuttx/irq.h" 3 4
int irq_attach_thread(int irq, xcpt_t isr, xcpt_t isrthread, void *arg,
                      int priority, int stack_size);
# 302 "../../include/nuttx/irq.h" 3 4
int irq_attach_wqueue(int irq, xcpt_t isr, xcpt_t isrwork,
                      void *arg, int priority);
# 34 "../../include/errno.h" 2 3 4
# 382 "../../include/errno.h" 3 4
 int *__errno(void);
# 32 "pwd/lib_getpwbufr.c" 2
# 1 "../../include/pwd.h" 1 3 4
# 49 "../../include/pwd.h" 3 4
struct passwd
{
  char *pw_name;
  char *pw_passwd;
  uid_t pw_uid;
  gid_t pw_gid;
  char *pw_gecos;
  char *pw_dir;
  char *pw_shell;
};
# 73 "../../include/pwd.h" 3 4
void setpwent(void);
void endpwent(void);
 struct passwd *getpwent(void);
int getpwent_r( struct passwd *pwd,
               char *buf, size_t buflen,
               struct passwd **result);
 struct passwd *getpwnam( const char *name);
 struct passwd *getpwuid(uid_t uid);
int getpwnam_r( const char *name, struct passwd *pwd, char *buf,
               size_t buflen, struct passwd **result);
int getpwuid_r(uid_t uid, struct passwd *pwd, char *buf,
               size_t buflen, struct passwd **result);
# 33 "pwd/lib_getpwbufr.c" 2

# 1 "./pwd/lib_pwd.h" 1
# 33 "./pwd/lib_pwd.h"
# 1 "../../include/shadow.h" 1 3 4
# 36 "../../include/shadow.h" 3 4
struct spwd
{
  char *sp_namp;
  char *sp_pwdp;
  long int sp_lstchg;
  long int sp_min;
  long int sp_max;
  long int sp_warn;
  long int sp_inact;
  long int sp_expire;
  unsigned long int sp_flag;
};







 struct spwd *getspnam( const char *name);
int getspnam_r( const char *name, struct spwd *sp, char *buf,
               size_t size, struct spwd **res);
# 34 "./pwd/lib_pwd.h" 2
# 66 "./pwd/lib_pwd.h"

# 66 "./pwd/lib_pwd.h"
extern int g_passwd_index;
extern struct passwd g_passwd;
extern struct spwd g_spwd;
extern char g_passwd_buffer[80];





 struct passwd *getpwbuf(uid_t uid, gid_t gid, const char *name,
                            const char *gecos, const char *dir,
                            const char *shell, const char *passwd);
int getpwbuf_r(uid_t uid, gid_t gid, const char *name,
               const char *gecos, const char *dir,
               const char *shell, const char *passwd,
               struct passwd *pwd, char *buf, size_t buflen,
               struct passwd **result);
# 35 "pwd/lib_getpwbufr.c" 2
# 68 "pwd/lib_getpwbufr.c"
int getpwbuf_r(uid_t uid, gid_t gid, const char *name,
               const char *gecos, const char *dir,
               const char *shell, const char *passwd,
               struct passwd *pwd, char *buf, size_t buflen,
               struct passwd **result)
{
  size_t reqdlen;
  size_t nsize;
  size_t gsize;
  size_t dsize;
  size_t ssize;
  size_t psize;

  nsize = strlen(name) + 1;
  gsize = strlen(gecos) + 1;
  dsize = strlen(dir) + 1;
  ssize = strlen(shell) + 1;
  psize = strlen(passwd) + 1;
  reqdlen = nsize + gsize + dsize + ssize + psize;

  if (buflen < reqdlen)
    {


      *result = 
# 92 "pwd/lib_getpwbufr.c" 3 4
               ((void*)0)
# 92 "pwd/lib_getpwbufr.c"
                   ;
      return 
# 93 "pwd/lib_getpwbufr.c" 3 4
            34
# 93 "pwd/lib_getpwbufr.c"
                  ;
    }

  pwd->pw_name = buf;
  pwd->pw_gecos = &buf[nsize];
  pwd->pw_dir = &buf[nsize + gsize];
  pwd->pw_shell = &buf[nsize + gsize + dsize];
  pwd->pw_passwd = &buf[nsize + gsize + dsize + ssize];

  pwd->pw_uid = uid;
  pwd->pw_gid = gid;
  strlcpy(pwd->pw_name, name, nsize);
  strlcpy(pwd->pw_gecos, gecos, gsize);
  strlcpy(pwd->pw_dir, dir, dsize);
  strlcpy(pwd->pw_shell, shell, ssize);
  strlcpy(pwd->pw_passwd, passwd, psize);

  *result = pwd;
  return 0;
}
