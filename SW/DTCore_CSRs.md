# DTCore Control and Status Registers (CSRs)

This document provides a comprehensive mapping of all the Control and Status Registers (CSRs) for the `DTCore` module, as defined in `DTCorev2_7_S_CTRL_AXI.sv`.

## Memory Map Overview

All registers are 32-bit wide and word-aligned. The base address of the AXI Slave interface applies to all offsets listed below.

| Offset | Register Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x000` | `CSR_CTRL` | R/W | Main control register for core operations, issue types, and data transfers |
| `0x004` | `CSR_STATUS_CORE_0` | RO | Core status regarding AGU readiness, tile status, and idle state |
| `0x008` | `CSR_STATUS_CORE_1` | RO | Detailed instruction status for the 4 core slots |
| `0x00C` | `CSR_STATUS_FIFO` | RO | Fill level status flags for IFB, IDBs, and ODB |
| `0x010` | `CSR_STATUS_MST` | RO | AXI Master transfer status and response flags |
| `0x014` | `CSR_ERR` | W1C | Hardware error flags (Write 1 to Clear) |
| `0x018` | `CSR_ISR` | W1C | Interrupt Status Register (Write 1 to Clear) |
| `0x01C` | `CSR_IER` | R/W | Interrupt Enable Register |
| `0x100` | `CSR_WM_IFB_HI` | R/W | Instruction Fetch Buffer (IFB) High Watermark |
| `0x104` | `CSR_WM_IFB_LO` | R/W | Instruction Fetch Buffer (IFB) Low Watermark |
| `0x108` | `CSR_WM_IDB0_HI` | R/W | Input Data Buffer 0 (IDB0) High Watermark |
| `0x10C` | `CSR_WM_IDB0_LO` | R/W | Input Data Buffer 0 (IDB0) Low Watermark |
| `0x110` | `CSR_WM_IDB1_HI` | R/W | Input Data Buffer 1 (IDB1) High Watermark |
| `0x114` | `CSR_WM_IDB1_LO` | R/W | Input Data Buffer 1 (IDB1) Low Watermark |
| `0x118` | `CSR_WM_IDB2_HI` | R/W | Input Data Buffer 2 (IDB2) High Watermark |
| `0x11C` | `CSR_WM_IDB2_LO` | R/W | Input Data Buffer 2 (IDB2) Low Watermark |
| `0x120` | `CSR_WM_IDB3_HI` | R/W | Input Data Buffer 3 (IDB3) High Watermark |
| `0x124` | `CSR_WM_IDB3_LO` | R/W | Input Data Buffer 3 (IDB3) Low Watermark |
| `0x280` | `CSR_TRACE_INST0` | RO | IFB Trace Data (Bits 31:0) |
| `0x284` | `CSR_TRACE_INST1` | RO | IFB Trace Data (Bits 63:32) |
| `0x288` | `CSR_TRACE_INST2` | RO | IFB Trace Data (Bits 95:64) |
| `0x28C` | `CSR_TRACE_INST3` | RO | IFB Trace Data (Bits 127:96) |
| `0x300` | `CSR_MS_W_ADDR_LO`| R/W | AXI Master Write Address (Low 32 bits) |
| `0x304` | `CSR_MS_W_ADDR_HI`| R/W | AXI Master Write Address (High 32 bits) |
| `0x308` | `CSR_MS_W_LEN` | R/W | AXI Master Write Burst Length |
| `0x310` | `CSR_MS_R_ADDR_LO`| R/W | AXI Master Read Address (Low 32 bits) |
| `0x314` | `CSR_MS_R_ADDR_HI`| R/W | AXI Master Read Address (High 32 bits) |
| `0x318` | `CSR_MS_R_LEN` | R/W | AXI Master Read Burst Length |

---

## Detailed Register Descriptions

### `CSR_CTRL` (0x000) - Control Register
| Bits | Name | Description |
| :--- | :--- | :--- |
| `0` | `DTC_EN` | Core Enable (`o_dtc_en`) |
| `1` | `SOFT_RST` | Soft Reset (Self-clearing pulse, `o_soft_rst`) |
| `2` | `IRQ_EN` | Global Interrupt Enable (`o_irq_en`) |
| `3` | `EXT_BUSY` | External Busy Signal Flag (`o_ext_busy`) |
| `6:4` | `ISSUE_TYPE` | Instruction Issue Type |
| `7` | `RD_START_PULSE` | Trigger AXI Master Read (1 cycle pulse, `o_m_r_start`) |
| `8` | `IFB_R_EN` | Instruction Fetch Buffer Read Enable (`o_ifb_r_en`) |
| `12:9` | `IDB_R_EN` | Input Data Buffer Read Enables (`[12]:IDB3`, `[11]:IDB2`, `[10]:IDB1`, `[9]:IDB0`) |
| `13` | `WR_START_PULSE` | Trigger AXI Master Write (1 cycle pulse, `o_m_w_start`) |
| `14` | `DST_SEL_INST` | Destination Select for instruction fetching (`o_dst_sel_inst`) |
| `16:15` | `DST_DATA_PORT`| Destination Data Port Select (`o_dst_data_port`) |
| `27:20` | `THREAD_ID` | Assigned Thread IDs (`[27:26]: Slot 3`, `[25:24]: Slot 2`, `[23:22]: Slot 1`, `[21:20]: Slot 0`) |

### `CSR_STATUS_CORE_0` (0x004) - Core Status 0
| Bits | Name | Description |
| :--- | :--- | :--- |
| `0` | `CORE_IDLE` | Indicates if the DTCore is currently idle |
| `1` | `ANY_TILEWB_FULL`| Indicates if any Tile Write-Back FIFO is full |
| `9:2` | `AGU_SLOT_READY` | AGU Slot Ready states (`[9:8]: Slot 3`, `[7:6]: Slot 2`, `[5:4]: Slot 1`, `[3:2]: Slot 0`) |
| `17:10` | `AGU_SLOT_BUSY` | AGU Slot Busy states (`[17:16]: Slot 3`, `[15:14]: Slot 2`, `[13:12]: Slot 1`, `[11:10]: Slot 0`) |
| `21:18` | `CORE_BUSY` | Core Busy flags per slot |
| `25:22` | `TILE_BUSY` | Tile Busy flags per slot |

### `CSR_STATUS_CORE_1` (0x008) - Core Status 1
| Bits | Name | Description |
| :--- | :--- | :--- |
| `23:0` | `INST_STATUS` | Instruction status fields mapped per slot (`[23:18]: Slot 3`, `[17:12]: Slot 2`, `[11:6]: Slot 1`, `[5:0]: Slot 0`) |

### `CSR_STATUS_FIFO` (0x00C) - FIFO Status
| Bits | Name | Description |
| :--- | :--- | :--- |
| `0` | `IFB_EMPTY` | Instruction Fetch Buffer is Empty |
| `1` | `IFB_FULL` | Instruction Fetch Buffer is Full |
| `5:2` | `IDB_EMPTY` | Input Data Buffer Empty states per buffer (`[5]: IDB3` to `[2]: IDB0`) |
| `9:6` | `IDB_FULL` | Input Data Buffer Full states per buffer (`[9]: IDB3` to `[6]: IDB0`) |
| `10` | `ODB_EMPTY` | Output Data Buffer is Empty |
| `11` | `ODB_FULL` | Output Data Buffer is Full |

### `CSR_STATUS_MST` (0x010) - AXI Master Status
| Bits | Name | Description |
| :--- | :--- | :--- |
| `0` | `M_TXN_DONE` | Master TX (Write to DDR) Transaction Done |
| `1` | `M_RXN_DONE` | Master RX (Read from DDR) Transaction Done |
| `2` | `M_ERROR` | Master general error flag |
| `4:3` | `LAST_BRESP` | Last AXI Write Response (BRESP) |
| `6:5` | `LAST_RRESP` | Last AXI Read Response (RRESP) |

### `CSR_ERR` (0x014) - Hardware Error Flags (Write 1 to Clear)
| Bits | Name | Description |
| :--- | :--- | :--- |
| `0` | `OP_ERROR` | Opcode decode error |
| `1` | `WB_CONFLICT` | Tile Write-Back conflict error |
| `2` | `AXI_WR_RESP_ERR`| AXI Write Response error (`BRESP != OKAY`) |
| `3` | `AXI_RD_RESP_ERR`| AXI Read Response error (`RRESP != OKAY`) |

### `CSR_ISR` (0x018) - Interrupt Status Register (Write 1 to Clear)
| Bits | Name | Description |
| :--- | :--- | :--- |
| `0` | `IRQ_OP_ERROR` | Triggered by an Opcode error |
| `1` | `IRQ_WB_CONFLICT`| Triggered by a Tile Write-Back conflict error |
| `2` | `IRQ_AXI_ERR` | Triggered by any AXI transaction error (BRESP, RRESP, or M_ERROR) |
| `3` | `IRQ_TX_DONE` | Triggered when AXI Master TX transaction finishes |
| `4` | `IRQ_RX_DONE` | Triggered when AXI Master RX transaction finishes |
| `5` | `IRQ_IFB_LOW` | Triggered when IFB depth falls below the Low Watermark |
| `6` | `IRQ_IDB_LOW` | Triggered when any IDB depth falls below its Low Watermark |
| `7` | `IRQ_ODB_FULL` | Triggered when the Output Data Buffer is full |

### `CSR_IER` (0x01C) - Interrupt Enable Register
Mirrors the layout of `CSR_ISR`. Setting a bit to `1` enables the corresponding interrupt to trigger `o_irq`.

### Watermark Registers (0x100 - 0x124)
Used to throttle the AXI Master to avoid buffer overflow/underflow.
- **High Watermark (`*_HI`)**: When a buffer's level is `>=` this value, data fetching/pushing is throttled to prevent overflow.
- **Low Watermark (`*_LO`)**: When a buffer's level is `<=` this value, fetching is resumed or an interrupt is triggered indicating that the buffer needs data.

### Trace Instructions (0x280 - 0x28C)
Read-only registers containing the latest fetched 128-bit instruction payload chunked into four 32-bit registers. Used for debugging or monitoring execution logic.

### Master AXI Configuration (0x300 - 0x318)
Registers corresponding to target Addresses and Burst Lengths for explicit memory copy commands via the integrated AXI Master.
- **Length Registers (`*_LEN`)**: Specifies the AXI burst length. Only the lowest 8 bits `[7:0]` are passed directly to `AWLEN/ARLEN`.