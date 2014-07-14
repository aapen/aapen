/*
 * raspi.h -- Raspberry Pi kernel definitions
 */
#ifndef _RASPI_H_
#define _RASPI_H_

#include "raspi.h"

typedef unsigned char u8;
typedef unsigned int u32;

/* Declare ARM assembly-language helper functions */
extern void PUT_32(u32 addr, u32 data);
extern u32 GET_32(u32 addr);
extern void NO_OP();
extern void BRANCH_TO(u32 addr);
extern void asm_copy32(u32* dst, u32* src, int len);

#endif /* _RASPI_H_ */
