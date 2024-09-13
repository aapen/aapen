#include "disasm/cstub.h"
#include "printf.h"
#include "disasm/aarch64.h"

uint64_t disassemble_stub(uint64_t addr) {
  char buf[256];
  uint64_t next = disasm(addr, buf);
  printf_("%08x    %s\n", addr, buf);
  return next;
}
