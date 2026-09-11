typedef struct _FILE FILE;
extern FILE* const stdout;
extern FILE* const stderr;

#define SEEK_SET 0
#define SEEK_END 2

int      printf(const char *, ...);
int      fprintf(FILE *, const char *, ...);
int      snprintf(char *, unsigned long, const char *, ...);
int      vsnprintf(char *, unsigned long, const char *, __builtin_va_list);
unsigned long fwrite(const void *, unsigned long, unsigned long, FILE *);
int      fflush(FILE *);
FILE    *fopen(const char *path, const char *mode);
int      fclose(FILE *);
int      putc(int, FILE *); int fputc(int, FILE *); int fputs(const char *, FILE *);
unsigned long fread(void *, unsigned long, unsigned long, FILE *);
int      fseek(FILE *, long, int);
long     ftell(FILE *);
