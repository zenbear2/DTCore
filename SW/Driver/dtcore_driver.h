#ifndef DTCORE_DRIVER_H
#define DTCORE_DRIVER_H

#include "xil_types.h"
#include "xil_io.h"

// =============================================================================
// Register Map Offsets (Byte Aligned)
// Based on DTCorev2_7_S_CTRL_AXI.sv
// =============================================================================
#define DTC_CSR_CTRL           0x00
#define DTC_CSR_STATUS_CORE_0  0x04
#define DTC_CSR_STATUS_CORE_1  0x08
#define DTC_CSR_STATUS_FIFO    0x0C
#define DTC_CSR_STATUS_MST     0x10
#define DTC_CSR_ERR            0x14
#define DTC_CSR_ISR            0x18
#define DTC_CSR_IER            0x1C

// DMA Configuration Registers (Master Read)
#define DTC_MS_R_ADDR_LO       0x310
#define DTC_MS_R_ADDR_HI       0x314
#define DTC_MS_R_LEN           0x318

// =============================================================================
// Bit Masks & Definitions
// =============================================================================

// CSR_CTRL Bits
#define DTC_CTRL_EN            (1 << 0)
#define DTC_CTRL_SOFT_RST      (1 << 1)
#define DTC_CTRL_IRQ_EN        (1 << 2)
#define DTC_CTRL_EXT_BUSY      (1 << 3)
#define DTC_CTRL_ISSUE_TYPE_S  4
// Bit 7: Read Start Pulse
#define DTC_CTRL_RD_START      (1 << 7)
// Bit 8: IFB Read Enable
#define DTC_CTRL_IFB_R_EN      (1 << 8)
// Bits 12:9: IDB Read Enable (4 ports)
#define DTC_CTRL_IDB0_R_EN     (1 << 9)
#define DTC_CTRL_IDB1_R_EN     (1 << 10)
#define DTC_CTRL_IDB2_R_EN     (1 << 11)
#define DTC_CTRL_IDB3_R_EN     (1 << 12)
// Bit 13: Write Start Pulse
#define DTC_CTRL_WR_START      (1 << 13)
// Bit 14: Destination Select (1=IFB, 0=IDB)
#define DTC_CTRL_DST_SEL_INST  (1 << 14)
// Bits 16:15: Data Port Select
#define DTC_CTRL_DST_PORT_S    15

// CSR_STATUS_MST Bits
#define DTC_MST_TXN_DONE       (1 << 0)
#define DTC_MST_RXN_DONE       (1 << 1)
#define DTC_MST_ERROR          (1 << 2)

// CSR_STATUS_CORE_0 Bits
#define DTC_CORE_IDLE          (1 << 0)

// =============================================================================
// Driver Function Prototypes
// =============================================================================

/**
 * Reset DTCore
 */
void DTCore_Reset(u32 BaseAddress);

/**
 * Load instructions to IFB (Instruction Fetch Buffer) via DMA
 * @param SrcAddr: External DDR source address (64-bit)
 * @param Length: Transfer length (Bytes)
 */
int DTCore_LoadInstructions(u32 BaseAddress, u64 SrcAddr, u32 Length);

/**
 * Load data to IDB (Input Data Buffer) via DMA
 * @param PortID: IDB Channel ID (0-3)
 * @param SrcAddr: External DDR source address (64-bit)
 * @param Length: Transfer length (Bytes)
 */
int DTCore_LoadData(u32 BaseAddress, u8 PortID, u64 SrcAddr, u32 Length);

/**
 * Start Core Computation
 * @param EnableIDB_Mask: Bitmask, e.g., 0x1 enables IDB0, 0xF enables all
 */
void DTCore_Start(u32 BaseAddress, u8 EnableIDB_Mask);

/**
 * Check if Core is Idle
 * @return 1 if Idle, 0 if Busy
 */
u32 DTCore_IsIdle(u32 BaseAddress);

#endif // DTCORE_DRIVER_H