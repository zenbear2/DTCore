# DTCore Compiler Guide & Contract

## **1. 架構摘要 (Architecture Summary)**

- **執行模型:** 128-bit VLIW (4-Slot MIMT-style)，靜態排程 (Static Scheduling)。
- **目標硬體:** FPGA (Xilinx ZCU102) @ 400MHz。
- **核心哲學:** 硬體負責「執行」與「結構性保護 (Stall)」，軟體負責「依賴解析」與「資源衝突避免」。

---

## **2. 記憶體模型與寫入合約 (RegFile Contract)**

RegFile 由 8 個 128-bit Banks 組成，物理上由 **32-bit BRAM Instances** 構成。

### **2.1 寫入通道物理綁定 (Source Binding)**

Lite 版移除了全互連 Crossbar，寫入來源被硬性分組：

| 來源 (Source)      | 物理連接埠 (Physical Port) | 允許寫入的數據類型                        |
| ---------------- | --------------------- | -------------------------------- |
| Tile 0, Tile 1   | Port A (Act Port)     | Activation, Intermediate Results |
| Tile 2, Tile 3   | Port B (Wei Port)     | Weights, Accumulation            |
| Core Input (DMA) | Port A & B (Muxed)    | 權限最低，需避開 Tile 寫回                 |

### **2.2 Bank 衝突定義 (Conflict Definition)**

**衝突發生的粒度是「32-bit Instance」。**

- **規則 A (同埠競爭):** Tile 0 與 Tile 1 共享 Port A。
   - **❌ 非法:** 同一 Cycle 寫入 **同一個 32-bit Slice** (例如都寫 Bank 0 [31:0])。
   - **✅ 合法 (Sub-bank):** 同一 Cycle 寫入 **同一個 Bank 的不同 Slice** (例如 Tile 0 寫 Bank 0 [31:0], Tile 1 寫 Bank 0)。
   - **✅ 合法 (Inter-bank):** 同一 Cycle 寫入 **不同 Bank**。
- **規則 B (跨埠並行):** Port A 與 Port B 獨立。
   - **✅ 合法:** Tile 0 (Port A) 與 Tile 2 (Port B) 可在同一 Cycle 寫入完全相同的 Bank 與 Slice。

---

## **3. 讀取路徑與 AGU 仲裁 (Read Path & Arbitration)**

### **3.1 移除 Bypass (No Core-to-Tile Bypass)**

- **合約:** Tile 無法直接讀取 Core Input。所有運算數據 **必須先寫入 RegFile**。
- **指令限制:** `100000 (Config)` 指令中，`Src` 欄位僅接受 `0` (Low Bank Group) 或 `1` (High Bank Group)。

### **3.2 AGU 優先級仲裁 (AGU Priority)**

`AGUvB1` 採用 **固定優先級 (Fixed Priority)**。

- **Slot 0 (High Priority):** 服務 `Thread 0, 1`。適用於 **關鍵路徑 (Critical Path)** 任務。
- **Slot 1 (Low Priority):** 服務 `Thread 2, 3`。適用於 **背景預取 (Prefetch)** 任務。
- **策略:** 若 Slot 0 有長 Burst 傳輸，必須將其 **切碎 (Slice)**，否則 Slot 1 會發生飢餓 (Starvation)。

---

## **4. 排程與同步 (Scheduling & Sync)**

### **4.1 顯式同步 (Explicit Synchronization)**

所有 RAW/WAR 依賴必須透過 `011000 (Block-Sync)` 指令解決。

- **順序:** `Write Operation` $\rightarrow$ `Block-Sync (Wait)` $\rightarrow$ `Read Operation`。

### **4.2 Ping-Pong 雙緩衝**

利用 Thread ID 進行 Bank Group 切換：

- **Phase A:** Compute on `Thread 0` (Read Bank A), DMA Write `Thread 1` (Write Bank B).
- **Phase B:** Compute on `Thread 1` (Read Bank B), DMA Write `Thread 0` (Write Bank A).

---

## **5. 數據佈局與格式 (Data Layout)**

### **5.1 矩陣 Tiling**

記憶體中的 Tensor 必須預先重排 (Swizzled) 為 **4x4 Blocks** 的線性序列，以配合 AGU 線性讀取。

### **5.2 數據封裝格式 (Data Packing)**

RegFile 的 32-bit 字組根據模式有不同定義：

#### **Dense / SIMD Mode (Mode 00/01)**

- **格式:** 4 個 8-bit Data (無壓縮)。
- **佈局:** `[Data 3][Data 2][Data 1][Data 0]`。

#### **Sparse Mode (Mode 11)**

- **格式:** **3:4 稀疏度** (3 個 Data + 4 個 Index)。
- **佈局:** `[Index 3..0 (8b)] [Data 2 (8b)] [Data 1 (8b)] [Data 0 (8b)]`。
   - **Index 區 (MSB 8-bit):** 每個 Index 佔 2-bit，對應原始 4 元素向量的位置。
   - **Data 區 (LSB 24-bit):** 依序存放非零值。若非零值少於 3 個，需填充 Padding (Data=0, Index=Don't Care)。

---

## **6. 違規後果對照表 (Violation Consequences)**

| 違規行為          | 硬體反應                  | 結果                       |
| ------------- | --------------------- | ------------------------ |
| 寫入同一 Sub-bank | Port MUX 衝突           | 數據損毀 (Silent Corruption) |
| 讀取 Source 2/3 | 讀取 SRAM 鏡像地址          | 計算錯誤                     |
| AGU Slot 0 獨佔 | AGU Slot 1 無法取得 Grant | 背景任務飢餓 / 效能下降            |
| 依賴圖有環         | Barrier 條件無法滿足        | 死鎖 (System Hang)         |

