#include "dtcore_driver.h"
#include "xil_printf.h"

// Simple delay function
static void DTCore_Delay(volatile u32 count) {
    while (count--) asm("nop");
}

void DTCore_Reset(u32 BaseAddress) {
    // Write Soft Reset (Bit 1)
    // Hardware has Self-clearing mechanism
    xil_out32(BaseAddress + DTC_CSR_CTRL, DTC_CTRL_SOFT_RST);
    
    // Wait a few cycles to ensure reset completion
    DTCore_Delay(100);
}

int DTCore_LoadInstructions(u32 BaseAddress, u64 SrcAddr, u32 Length) {
    u32 ctrl_val = 0;
    u32 status = 0;

    // 1. Set DMA source address and length
    xil_out32(BaseAddress + DTC_MS_R_ADDR_LO, (u32)(SrcAddr & 0xFFFFFFFF));
    xil_out32(BaseAddress + DTC_MS_R_ADDR_HI, (u32)((SrcAddr >> 32) & 0xFFFFFFFF));
    xil_out32(BaseAddress + DTC_MS_R_LEN, Length);

    // 2. Set transfer destination to IFB (Instruction FIFO) and trigger read
    // Bit 14 (DST_SEL_INST) = 1
    // Bit 7  (RD_START) = 1
    ctrl_val = DTC_CTRL_DST_SEL_INST | DTC_CTRL_RD_START;
    xil_out32(BaseAddress + DTC_CSR_CTRL, ctrl_val);

    // 3. Poll for transfer completion (RX Done)
    // Note: A Timeout mechanism is recommended for real applications
    do {
        status = xil_in32(BaseAddress + DTC_CSR_STATUS_MST);
    } while ((status & DTC_MST_RXN_DONE) == 0);

    // 4. Clear status (CSR_ISR W1C; although STATUS_MST is read-only reflecting status, usually clear interrupt bit via ISR)
    // Assuming STATUS_MST resets on next Start Pulse, or ISR needs clearing
    xil_out32(BaseAddress + DTC_CSR_ISR, DTC_MST_RXN_DONE); // Clear RX Done interrupt bit

    if (status & DTC_MST_ERROR) {
        xil_printf("[DTC Driver] Error loading instructions!\r\n");
        return -1;
    }

    return 0;
}

int DTCore_LoadData(u32 BaseAddress, u8 PortID, u64 SrcAddr, u32 Length) {
    u32 ctrl_val = 0;
    u32 status = 0;

    if (PortID > 3) return -1;

    // 1. Set DMA source address and length
    xil_out32(BaseAddress + DTC_MS_R_ADDR_LO, (u32)(SrcAddr & 0xFFFFFFFF));
    xil_out32(BaseAddress + DTC_MS_R_ADDR_HI, (u32)((SrcAddr >> 32) & 0xFFFFFFFF));
    xil_out32(BaseAddress + DTC_MS_R_LEN, Length);

    // 2. Set transfer destination to IDB (Input Data Buffer)
    // Bit 14 (DST_SEL_INST) = 0
    // Bits 16:15 (DST_PORT) = PortID
    // Bit 7 (RD_START) = 1
    ctrl_val = (PortID << DTC_CTRL_DST_PORT_S) | DTC_CTRL_RD_START;
    
    // Clear DST_SEL_INST bit to ensure IDB is selected
    ctrl_val &= ~DTC_CTRL_DST_SEL_INST; 

    xil_out32(BaseAddress + DTC_CSR_CTRL, ctrl_val);

    // 3. Poll for transfer completion
    do {
        status = xil_in32(BaseAddress + DTC_CSR_STATUS_MST);
    } while ((status & DTC_MST_RXN_DONE) == 0);

    // 4. Clear ISR
    xil_out32(BaseAddress + DTC_CSR_ISR, DTC_MST_RXN_DONE);

    if (status & DTC_MST_ERROR) {
        xil_printf("[DTC Driver] Error loading data to Port %d!\r\n", PortID);
        return -1;
    }

    return 0;
}

void DTCore_Start(u32 BaseAddress, u8 EnableIDB_Mask) {
    u32 ctrl_val = 0;

    // Basic settings:
    // Bit 0: Enable Core
    // Bit 8: Enable IFB Read (Core instruction fetch)
    ctrl_val = DTC_CTRL_EN | DTC_CTRL_IFB_R_EN;

    // Enable corresponding IDB read channels based on Mask
    if (EnableIDB_Mask & 0x1) ctrl_val |= DTC_CTRL_IDB0_R_EN;
    if (EnableIDB_Mask & 0x2) ctrl_val |= DTC_CTRL_IDB1_R_EN;
    if (EnableIDB_Mask & 0x4) ctrl_val |= DTC_CTRL_IDB2_R_EN;
    if (EnableIDB_Mask & 0x8) ctrl_val |= DTC_CTRL_IDB3_R_EN;

    // Write to Control Register
    // Note: This overwrites previous settings (like issue_type); use Read-Modify-Write to preserve
    // Assuming fresh start
    xil_out32(BaseAddress + DTC_CSR_CTRL, ctrl_val);

    xil_printf("[DTC Driver] Core Started. CTRL=0x%08x\r\n", ctrl_val);
}

u32 DTCore_IsIdle(u32 BaseAddress) {
    u32 status = xil_in32(BaseAddress + DTC_CSR_STATUS_CORE_0);
    return (status & DTC_CORE_IDLE) ? 1 : 0;
}