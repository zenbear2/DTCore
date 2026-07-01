# **Instruction Format Overview **

### **1.1 VLIW Bundle Layout**

```other
| 127 ............ 96 | 95 ............ 64 | 63 ............ 32 | 31 ............. 0 |
|      Issue-Lane 3   |    Issue-Lane 2    |     Issue-Lane 1   |    Issue-Lane 0    |
```

- **平行性 (Parallelism):** 4 個 Issue-Lane 解碼完全獨立，可以對自身管理的硬體資源（如 AGU、Tile、RegFile Port）發出指令。
- **解碼 (Decoding):** 每個 Issue-Lane 都有獨立的 `SubDecoder`。雖然指令格式是通用的，但通常編譯器會依照硬體資源分組來安排指令（例如 Issue-Lane 0/1 控制 Act Bank，Issue-Lane 2/3 控制 Weight Bank）。
- **資源管理:** Issue-Lane 0 管理 Low Bank Act Port、 Issue-Lane 1 管理 High Bank Act Port 、Issue-Lane 2 管理 Low Bank Weight Port、Issue-Lane 3 管理 High Bank Weight Port。

### **1.2 Sub-Instruction Format (32-bit)**

所有子指令遵循統一的 `Opcode + Payload` 結構：

#### R-Type T-Type

| Bit Range | Field Name | Description                                   |
| --------- | ---------- | --------------------------------------------- |
| [31:26]   | Opcode     | 6-bit 操作碼，決定指令類型 (除TileWB外的RegFile 或 Tile 操作) |
| [25:0]    | Payload    | 26-bit 參數欄位，根據 Opcode 定義不同功能                  |

#### TileWB only

| Bit Range | Field Name | Description              |
| --------- | ---------- | ------------------------ |
| [31:30]   | Opcode     | 2-bit 操作碼，進限於TileWB      |
| [29:0]    | Payload    | 30-bit 參數欄位，根據 TileWB 定義 |

---

## **2. 指令詳細定義 (Instruction Reference)**

Opcode 高位元區分了兩大類操作：

- `0xxxxx`: **RegFile & AGU Operations** (記憶體存取、同步)
- `1xxxxx`: **Tile Operations** (運算組態、啟動)
- `11`: **TileWB** (寫回)

---

### **A. RegFile & Control Group (Opcode: 0xxxxx)**

此類指令控制記憶體子系統 (`RegFile`, `AGU`) 與執行流 (`Barrier`).

#### `000000`**: Tile Write-back Setup**(R_TWB) **(Tile 寫回通道設定)**

設定 RegFile 的寫入埠 MUX，允許 Tile 的輸出寫入特定的 Bank。

- **適用場景:** 在 Tile 計算完成前發出，為寫回數據「鋪路」。
- **精簡版 (Lite) 限制:** 必須遵守 Tile ID 與 Port 的物理綁定。
   - Tile 0, 1 只能透過 `Act_Port` 寫入。
   - Tile 2, 3 只能透過 `Wei_Port` 寫入。

| Bits   | Field         | Description                                                                           |
| ------ | ------------- | ------------------------------------------------------------------------------------- |
| [11:0] | Source_Select | 4組 3-bit 選擇信號，分別對應 RegFile 1個 Port 的 4個BRAM 32-bit Port。<br>  <br>設定值 0~3 對應 Tile ID。 |

#### `001000`**: Core Input Write**(R_CW) **(外部數據寫入)**

啟動 DMA/AXI Master 將數據從外部寫入 RegFile。

- **Payload:** `20-bit`

| Bits    | Field     | Description                           |
| ------- | --------- | ------------------------------------- |
| [23:22] | Stream_ID | 標記此任務的 ID (0-3)，用於 Ping-Pong 切換與依賴追蹤。 |
| [21:20] | Resvered  | 保留                                    |
| [19:10] | Length    | 寫入長度 (以 128-bit 為單位)。寫入的資料數為Length+1  |
| [9:0]   | Address   | RegFile 內部的起始地址 (0~1023)。             |

#### `010000`**: Read / AGU Start**(R_R) **(讀取數據給 Tile)**

啟動 AGU，從 RegFile 讀取數據並送往 Tile 的 Row/Col Buffer。這是觸發計算的前置動作之一。AGU 內有兩個 Context ，Context-0 可放入 stream_id 0/1 的任務 Context-1 則可放入 stream_id 2/3 的任務，Context-0 優先級大於 Context-1

- **Payload:** `24-bit`

| Bits    | Field     | Description                               |
| ------- | --------- | ----------------------------------------- |
| [23:22] | Stream_ID | 標記此任務的 ID (0-3)，用於 Ping-Pong 切換與依賴追蹤。     |
| [21:20] | Interval  | 地址生成的間隔(0:無間隔,1為間隔1-Cycle etc.)(interval) |
| [19:10] | Length    | 讀取長度。發送的資料數為Length+1                      |
| [9:0]   | Address   | RegFile 起始地址。                             |

#### `011000`**: Block-Sync**(B_SYNC) **(屏障同步)**

**這是架構的核心。** 強制當前 Slot 暫停 Fetch，直到滿足特定條件。實現 MIMT 風格的同步。此處的 **AGU_CTX** -0/1 指的是 Context`- 0/1`

- **Payload:** `14-bit`

| Bits   | Field          | Description                                                                                                 |
| ------ | -------------- | ----------------------------------------------------------------------------------------------------------- |
| [13:8] | Status         | (Reserved/Debug) 目前狀態回報位。                                                                                   |
| [7]    | Wait_Tile      | 1: 等待本 Slot 對應的 Tile 變為 Idle (計算完成)。                                                                        |
| [6]    | Wait_AGU_CTX_1 | 1: 等待本 AGU Context-1 完成。stream_id 2,3 會在這個 Context                                                          |
| [5]    | Wait_AGU_CTX_0 | 1: 等待本 AGU Context-0 完成。stream_id 0,1 會在這個 Context                                                          |
| [4]    | Ext_Wait       | 1: 等待外部信號 (如 AXI DMA 完成)。                                                                                   |
| [3:0]  | Sync_Mask      | Barrier Mask。指定要等待哪些其他 issue lane。本 issue lane的自身對應bit會被忽略。<br>  <br>例如 4'b0011 表示等待 Slot 0 和 Slot 1 的任務完成。 |

---

### **B. Tile Compute Group (Opcode: 10xxxx)**

此類指令直接控制 4x4 PE 陣列的行為。

#### `100000`**: Configuration**(T_SCM) **(計算組態設定)**

設定 PE 的數據來源、模式與後處理參數。此指令**不啟動**計算，僅設定狀態。

- **Payload:** `17-bit`

| Bits    | Field         | Description                                |
| ------- | ------------- | ------------------------------------------ |
| [16]    | Clear_Out     | 1: 清除 PE 的輸出暫存器 (Accumulator Output)。      |
| [15]    | Clear_Acc     | 1: 清除 PE 內部的 P-Reg (累加器歸零)。                |
| [14]    | ReLU          | 1: 啟用 ReLU 激活函數 (負值歸零)。                    |
| [13:10] | Mode          | [3:2]PE 連續啟動 Clock [1:0] PE 模式             |
| [9:8]   | Wei_Stream_ID | 指定 Weight 數據應匹配的 Stream ID (用於安全檢查)。       |
| [7:5]   | Wei_Src       | 精簡版限制: 僅 LSB 有效。0: Low Bank, 1: High Bank。 |
| [4:3]   | Act_Stream_ID | 指定 Act 數據應匹配的 Stream ID。                   |
| [2:0]   | Act_Src       | 精簡版限制: 僅 LSB 有效。0: Low Bank, 1: High Bank。 |

**PE Mode 設定**

| Patten  | Description           |
| ------- | --------------------- |
| 4'b0000 | Spraity Systolic  1:4 |
| 4'b0100 | Spraity Systolic  2:4 |
| 4'b1000 | Spraity Systolic  3:4 |
| 4'b1100 | Dense  Systolic  4:4  |
| 4'b0001 | SIMD                  |
| 4'b1110 | SCALE                 |

#### `101000`**: Enable Compute**(T_ENC) **(啟動計算)**

**Kick-off 指令。** 帶入量化參數，並正式啟動 PE Array 的狀態機。

- **Payload:** `24-bit`

| Bits    | Field      | Description                                           |
| ------- | ---------- | ----------------------------------------------------- |
| [23:16] | Zero_Point | 8-bit Zero Point (用於非對稱量化)。Ver.Lite NO this function. |
| [15:0]  | Scale      | 16-bit Scale Factor (用於定點量化乘法)。實際只有15-bit Unsigned    |

#### `11xxxxx`**: Tile Write-back**(T_WB) **(計算結果寫回)**

控制 Tile 如何將計算結果輸出並寫入 FIFO。

- **Payload:** `30-bit`

| Bits    | Field      | Description                                                                                                   |
| ------- | ---------- | ------------------------------------------------------------------------------------------------------------- |
| [29:26] | Mask       | WriteBack Mask for Sub-BRAM Port. 允許資料寫入 對 Tile 開放的RegFile Bank Port(128-bit) 的 Sub-BRAM Port(32-bit)         |
| [25:18] | DABus_Sel  | Diagonal Access Bus Select。<br>  <br>這是一個 Bitmask (8-bit)，用於啟動對角線輸出波前 (Start Pulse Broadcast)。通常設為特定 Pattern。 |
| [17:10] | Reorder    | 控制 Reorder Buffer 的行為，將脈動陣列的傾斜輸出重組為線性格式。                                                                      |
| [9:0]   | WB_Address | 指定寫回 RegFile 的目標地址。                                                                                           |

#### `101100`**: Core Output**(C_OUT) **(數據輸出)**

控制 Core 的輸出 MUX，將 RegFile 中的數據送往 `ODB` (Output Data Buffer) 最終輸出到 AXI。

- **Payload:** `5-bit`

| Bits  | Field        | Description                              |
| ----- | ------------ | ---------------------------------------- |
| [4:3] | Stream_ID    | 選擇要輸出的數據屬於哪個 Stream (確保數據就緒)。            |
| [2]   | Select_Valid | 1: 輸出有效。                                 |
| [1:0] | Source       | 選擇數據來源 (0/1: Act Banks, 2/3: Wgt Banks)。 |

