#ifndef _BOOT_H
#define _BOOT_H

// 64Kb Stack size per core
#define STACK_SIZE                           0x10000

// System Control Register
#define SCTLR_RES1                           (3 << 28) | (3 << 22) | (1 << 20) | (1 << 11)
#define SCTLR_DCACHE_ENABLED                 (1 << 2)
#define SCTLR_ICACHE_ENABLED                 (1 << 12)
#define SCTLR_NAA_DISABLED                   (1 << 6)
#define SCTLR_EL1_VALUE                      (SCTLR_RES1 | SCTLR_DCACHE_ENABLED | SCTLR_ICACHE_ENABLED | SCTLR_NAA_DISABLED)

// Counter Hardware Control
// Do not trap accesses to the physical or virtual counters from EL1
#define CNTHCTL_EL1PCTEN_DISABLE             (1 << 10)
#define CNTHCTL_EL1PTEN_DISABLE              (1 << 11)
#define CNTHCTL_EL2_VALUE                    (CNTHCTL_EL1PCTEN_DISABLE | CNTHCTL_EL1PTEN_DISABLE)

// Feature Access Control
// Zig and LLVM like to use vector registers. We must disable traps on
// the SIMD/FPE instructions for that to work.
#define CPACR_ZEN_TRAP_NONE                  (3 << 16)
#define CPACR_FPEN_TRAP_NONE                 (3 << 20)
#define CPACR_TTA_DISABLE                    (0 << 28)
#define CPACR_EL1_VALUE                      (CPACR_ZEN_TRAP_NONE | CPACR_FPEN_TRAP_NONE | CPACR_TTA_DISABLE)

// Hypervisor Configuration
#define HCR_RW_EL1_IS_AARCH64                (1 << 31)
#define HCR_EL2_VALUE                        (HCR_RW_EL1_IS_AARCH64)

// Saved Program Status Register
#define SPSR_MODE_EL1H                       (0x5 << 0)
#define SPSR_MASK_ALL_EXCEPTIONS             (0xf << 6)
#define SPSR_EL1_TRANSITION_VALUE            (SPSR_MODE_EL1H | SPSR_MASK_ALL_EXCEPTIONS)

#endif // _BOOT_H
