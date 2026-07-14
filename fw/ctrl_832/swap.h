#ifndef SWAP_H
#define SWAP_H

static inline unsigned long SwapBBBB(unsigned long i) {
#ifdef _M68K
    asm volatile("rol.w #8,%0\n\t"
                 "swap %0\n\t"
                 "rol.w #8,%0\n\t"
                 : "=r"(i) /* out */
                 : "r"(i)
                 : /* no clobber */
    );
    return i;
#else
    int result = (i >> 24) & 0xff;
    result |= (i >> 8) & 0xff00;
    result |= (i << 8) & 0xff0000;
    result |= (i << 24) & 0xff000000;
    return (result);
#endif
}

static inline unsigned int SwapBB(unsigned int i) {
    int result = (i >> 8) & 0xff;
    result |= (i << 8) & 0xff00;
    return (result);
}

static inline unsigned long SwapWW(unsigned long i) {
    int result = (i >> 16) & 0xffff;
    result |= (i << 16) & 0xffff0000;
    return (result);
}

#endif

