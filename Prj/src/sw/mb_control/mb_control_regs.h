#ifndef MB_CONTROL_REGS_H
#define MB_CONTROL_REGS_H

#include <stdint.h>

#define MB_DAC_BASE_ADDR      0xC0000000u

#define MB_REG_IDENT          0x000u
#define MB_REG_VERSION        0x004u
#define MB_REG_STATUS0        0x008u
#define MB_REG_STATUS1        0x00cu
#define MB_REG_CONTROL        0x010u
#define MB_REG_COMMAND        0x014u
#define MB_REG_SCALE01        0x018u
#define MB_REG_SCALE23        0x01cu
#define MB_REG_FTW0_LO        0x020u
#define MB_REG_FTW0_HI        0x024u
#define MB_REG_FTW1_LO        0x028u
#define MB_REG_FTW1_HI        0x02cu
#define MB_REG_FTW2_LO        0x030u
#define MB_REG_FTW2_HI        0x034u
#define MB_REG_FTW3_LO        0x038u
#define MB_REG_FTW3_HI        0x03cu
#define MB_REG_RF_SWITCH      0x040u
#define MB_REG_ATTEN01        0x044u
#define MB_REG_ATTEN23        0x048u
#define MB_REG_RF_FLAGS       0x04cu
#define MB_REG_DAC_PROFILE    0x050u
#define MB_REG_UPDATE_CNT     0x054u

#define MB_CONTROL_ENABLE     0x00000001u
#define MB_CONTROL_RESET_PHASE 0x00000002u

#define MB_COMMAND_APPLY      0x00000001u
#define MB_COMMAND_RESET_PHASE 0x00000002u
#define MB_COMMAND_CLEAR_COUNT 0x00000100u

static inline void mb_reg_write(uint32_t offset, uint32_t value)
{
    volatile uint32_t *reg =
        (volatile uint32_t *)(uintptr_t)(MB_DAC_BASE_ADDR + offset);
    *reg = value;
}

static inline uint32_t mb_reg_read(uint32_t offset)
{
    volatile uint32_t *reg =
        (volatile uint32_t *)(uintptr_t)(MB_DAC_BASE_ADDR + offset);
    return *reg;
}

static inline void mb_write_ftw(unsigned channel, uint64_t ftw)
{
    uint32_t low = (uint32_t)(ftw & 0xffffffffu);
    uint32_t high = (uint32_t)((ftw >> 32) & 0xffffu);

    switch (channel) {
    case 0:
        mb_reg_write(MB_REG_FTW0_LO, low);
        mb_reg_write(MB_REG_FTW0_HI, high);
        break;
    case 1:
        mb_reg_write(MB_REG_FTW1_LO, low);
        mb_reg_write(MB_REG_FTW1_HI, high);
        break;
    case 2:
        mb_reg_write(MB_REG_FTW2_LO, low);
        mb_reg_write(MB_REG_FTW2_HI, high);
        break;
    default:
        mb_reg_write(MB_REG_FTW3_LO, low);
        mb_reg_write(MB_REG_FTW3_HI, high);
        break;
    }
}

#endif
