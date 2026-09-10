#ifndef STUB_MATH_H
#define STUB_MATH_H

#define signbit(x) (sizeof(x) == 4 \
    ? (((union { float f; unsigned u; }){x}.u & 0x80000000u) != 0) \
    : (((union { double f; unsigned long u; }){x}.u & 0x8000000000000000UL) != 0))
#define isnan(x) ((x) != (x))
#define isinf(x) (sizeof(x) == 4 \
    ? (((union { float f; unsigned u; }){x}.u & 0x7fffffff) == 0x7f800000) \
    : (((union { double f; unsigned long u; }){x}.u & 0x7fffffffffffffffUL) == 0x7ff0000000000000UL))

float  copysignf(float x, float y);   double copysign(double x, double y);
float  fabsf(float x);                double fabs(double x);
float  ceilf(float x);                double ceil(double x);
float  floorf(float x);               double floor(double x);
float  truncf(float x);               double trunc(double x);
float  rintf(float x);                double rint(double x);
float  sqrtf(float x);                double sqrt(double x);

#endif
