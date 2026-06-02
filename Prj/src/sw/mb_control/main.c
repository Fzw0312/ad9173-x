#include "mb_control_regs.h"

#define DEFAULT_DAC0_FTW 0x053555555555ull
#define DEFAULT_DAC1_FTW 0x07d000000000ull

int main(void)
{
    mb_reg_write(MB_REG_CONTROL, 0u);

    mb_write_ftw(0u, DEFAULT_DAC0_FTW);
    mb_write_ftw(1u, DEFAULT_DAC1_FTW);
    mb_write_ftw(2u, DEFAULT_DAC0_FTW);
    mb_write_ftw(3u, DEFAULT_DAC1_FTW);
    mb_reg_write(MB_REG_SCALE01, 0x7fff7fffu);
    mb_reg_write(MB_REG_SCALE23, 0x7fff7fffu);

    mb_reg_write(MB_REG_RF_SWITCH, 0u);
    mb_reg_write(MB_REG_ATTEN01, 0u);
    mb_reg_write(MB_REG_ATTEN23, 0u);
    mb_reg_write(MB_REG_RF_FLAGS, 0u);
    mb_reg_write(MB_REG_DAC_PROFILE, 0x00000201u);

    mb_reg_write(MB_REG_CONTROL,
                 MB_CONTROL_ENABLE | MB_CONTROL_RESET_PHASE);
    mb_reg_write(MB_REG_COMMAND,
                 MB_COMMAND_APPLY | MB_COMMAND_RESET_PHASE);

    while (1) {
        (void)mb_reg_read(MB_REG_STATUS0);
    }

    return 0;
}
