import json
import os
import numpy as np

class DTCoreCompiler:
    def __init__(self, config_path="dtcore_config.json"):
        self.instructions = []
        self.data_act = []
        self.data_wgt = []
        
        # =================================================================
        # 1. 載入並解析 JSON 設定檔
        # =================================================================
        if not os.path.exists(config_path):
            print(f"[Warning] Config file '{config_path}' not found. Using defaults.")
            self.config = {}
        else:
            with open(config_path, 'r') as f:
                self.config = json.load(f)

        # 2. 提取關鍵參數 [Full JSON Hierarchy Support]
        self.sys_info = self.config.get("system_info", {})
        
        # Timing & Safety
        timing = self.config.get("timing_model", {})
        self.delays = timing.get("frontend", {"decode_latency": 2})
        self.wb_stages = timing.get("writeback", {"t_wb_pipeline_depth": 3})
        self.safety = timing.get("safety", {"requires_double_sync": False})
        
        # Modes & Patterns
        self.modes = self.config.get("compute_modes", {})
        self.wb_patterns_cfg = self.config.get("wb_patterns", {})
        self.hw_limits = self.config.get("hardware_constraints", {})

        # 3. 定義指令 Opcode (對應 SystemVerilog)
        self.OP_R_TWB  = 0b000000 # 0x00
        self.OP_R_CW   = 0b001000 # 0x08
        self.OP_R_R    = 0b010000 # 0x10
        self.OP_B_S    = 0b011000 # 0x18
        self.OP_T_SCM  = 0b100000 # 0x20
        self.OP_T_ENC  = 0b101000 # 0x28
        self.OP_C_OUT  = 0b101100 # 0x2C
        self.OP_T_WB_TOP = 0b11   # Special 2-bit Opcode for T_WB

        # 4. 動態生成模式屬性 (例如 compiler.MODE_DENSE_4_4)
        for name, data in self.modes.items():
            if name != "description":
                # 儲存模式的 bits，方便調用
                setattr(self, f"MODE_{name}", data["mode_bits"])

        # 5. 定義指令 Payload 的欄位常數 (取代 Magic Numbers)
        # R_R (Read / AGU)
        self.RR_THREAD_ID_SHIFT = 22
        self.RR_MODE_SHIFT = 20
        self.RR_LEN_SHIFT = 10
        self.RR_ADDR_SHIFT = 0
        self.RR_THREAD_ID_MASK = 0x3
        self.RR_MODE_MASK = 0x3
        self.RR_LEN_MASK = 0x3FF
        self.RR_ADDR_MASK = 0x3FF
        # B_S (Sync)
        self.BS_WAIT_TILE_SHIFT = 7
        self.BS_WAIT_AGU1_SHIFT = 6
        self.BS_WAIT_AGU0_SHIFT = 5
        self.BS_EXT_WAIT_SHIFT = 4
        self.BS_SYNC_MASK_SHIFT = 0
        self.BS_WAIT_MASK = 0x1
        self.BS_SYNC_MASK = 0xF


    # =========================================================================
    # 核心組譯函式 (Low-Level Assembly)
    # =========================================================================
    
    def make_inst(self, opcode, payload):
        """組合 Opcode (6-bit) 與 Payload (26-bit)"""
        return ((opcode & 0x3F) << 26) | (payload & 0x03FFFFFF)

    def add_vliw_inst(self, slot3, slot2, slot1, slot0, comment=""):
        """
        生成 128-bit VLIW 指令包
        Format: [Slot3][Slot2][Slot1][Slot0] (Hex String)
        """
        hex_str = f"{slot3:08X}{slot2:08X}{slot1:08X}{slot0:08X}"
        self.instructions.append(f"{hex_str} // {comment}")

    def nop(self):
        """生成 NOP 指令 (空的 B_SYNC)"""
        return self.gen_b_sync(0, 0, 0, 0, 0)

    # --- 指令生成器 (Instruction Generators) ---

    def gen_r_cw(self, length, address):
        """Core Input Write"""
        payload = ((length & 0x3FF) << 10) | (address & 0x3FF)
        return self.make_inst(self.OP_R_CW, payload)

    def gen_r_r(self, length, address, thread_id=0, mode=0):
        """Read / AGU Start. 'mode' controls AGU behavior for sparsity."""
        payload = (
            ((thread_id & self.RR_THREAD_ID_MASK) << self.RR_THREAD_ID_SHIFT) |
            ((mode & self.RR_MODE_MASK) << self.RR_MODE_SHIFT) |
            ((length & self.RR_LEN_MASK) << self.RR_LEN_SHIFT) |
            ((address & self.RR_ADDR_MASK) << self.RR_ADDR_SHIFT)
        )
        return self.make_inst(self.OP_R_R, payload)

    def gen_b_sync(self, wait_tile=0, wait_agu1=0, wait_agu0=0, ext_wait=0, sync_mask=0):
        """Block-Sync / Barrier"""
        payload = (
            ((wait_tile & self.BS_WAIT_MASK) << self.BS_WAIT_TILE_SHIFT) |
            ((wait_agu1 & self.BS_WAIT_MASK) << self.BS_WAIT_AGU1_SHIFT) |
            ((wait_agu0 & self.BS_WAIT_MASK) << self.BS_WAIT_AGU0_SHIFT) |
            ((ext_wait & self.BS_WAIT_MASK) << self.BS_EXT_WAIT_SHIFT) |
            ((sync_mask & self.BS_SYNC_MASK) << self.BS_SYNC_MASK_SHIFT)
        )
        return self.make_inst(self.OP_B_S, payload)

    def gen_t_scm(self, mode, relu=0, clr_acc=0, clr_out=0, wei_tid=0, wei_src=0, act_tid=0, act_src=0):
        """Tile Configuration"""
        payload = ((clr_out & 1) << 16) | ((clr_acc & 1) << 15) | ((relu & 1) << 14) | \
                  ((mode & 0xF) << 10) | ((wei_tid & 0x3) << 8) | ((wei_src & 0x7) << 5) | \
                  ((act_tid & 0x3) << 3) | (act_src & 0x7)
        return self.make_inst(self.OP_T_SCM, payload)

    def gen_t_enc(self, scale, zero_point=0):
        """Enable Compute / Set Global Quantization Params"""
        payload = ((zero_point & 0xFF) << 16) | (scale & 0xFFFF)
        return self.make_inst(self.OP_T_ENC, payload)

    def gen_t_wb(self, wb_addr, mask=0, dabus_sel=0, reorder=0):
        """Tile Write-Back (Special 2-bit Opcode)"""
        inst = ((self.OP_T_WB_TOP & 0x3) << 30) | \
               ((mask & 0xF) << 26) | \
               ((dabus_sel & 0xFF) << 18) | \
               ((reorder & 0xFF) << 10) | \
               (wb_addr & 0x3FF)
        return inst
        
    def gen_c_out(self, thread_id=0, valid=1, src_select=0):
        """Core Output"""
        payload = ((thread_id & 0x3) << 3) | ((valid & 1) << 2) | (src_select & 0x3)
        return self.make_inst(self.OP_C_OUT, payload)

    # =========================================================================
    # 智慧型功能 (Smart Functions)
    # =========================================================================

    def _pack_pattern_list(self, value_list):
        """Helper: 將 JSON 中的 [3, 2, 1, 0] 列表打包成 8-bit 整數"""
        packed = 0
        for i, val in enumerate(value_list):
            # List[0] is MSB (Bits 7:6)
            shift = (3 - i) * 2
            packed |= (val & 0x3) << shift
        return packed

    def gen_t_wb_smart_flush(self, wb_addr, pattern_prefix="ROW"):
        """
        根據 JSON 設定自動生成 4 條 T_WB 指令，將 4x4 Tile 拼回 128-bit RegFile。
        支援 "ROW" (標準) 或 "COL" (轉置)。
        """
        insts = []
        for i in range(4):
            key = f"{pattern_prefix}_{i}"
            
            if key in self.wb_patterns_cfg:
                cfg = self.wb_patterns_cfg[key]
                # [Auto-Pack List to Int]
                da_val = self._pack_pattern_list(cfg["da_bus"])
                re_val = self._pack_pattern_list(cfg["reorder"])
            else:
                raise ValueError(f"Pattern {key} not found in config file!")

            # Mask: 0001 -> 0010 -> 0100 -> 1000 (Sequential Write)
            mask = 1 << i 
            insts.append(self.gen_t_wb(wb_addr, mask=mask, dabus_sel=da_val, reorder=re_val))
        return insts

    # =========================================================================
    # High-Level Flow (Persistent T_ENC Model)
    # =========================================================================

    def _insert_decode_delay(self):
        """插入解碼延遲所需的 NOP 指令"""
        for _ in range(self.delays.get("decode_latency", 2)):
            self.add_vliw_inst(self.nop(), self.nop(), self.nop(), self.nop(), "Decode Delay")

    def compile_init_layer(self, mode_name, scale=1, zero_point=0):
        """
        [Phase 1] 初始化層級：設定模式、清除 Acc，並開啟持續計算開關 (T_ENC)。
        此函式每層只呼叫一次。
        """
        if mode_name not in self.modes:
            raise ValueError(f"Unknown mode: {mode_name}")
        
        mode_val = self.modes[mode_name]["mode_bits"]
        
        # 1. Config Mode (T_SCM)
        # 初始狀態：清空 ACC，清空 Output，設定 Act 來自 Low Bank (Src=0), Wgt 來自 High Bank (Src=1)
        inst_scm = self.gen_t_scm(mode=mode_val, clr_acc=1, clr_out=1, act_src=0, wei_src=1)
        self.add_vliw_inst(self.nop(), self.nop(), self.nop(), inst_scm, f"Init Layer: {mode_name}")
        
        self._insert_decode_delay()

        # 2. Safety Sync (若 JSON 要求)
        if self.safety.get("requires_double_sync", False):
            self.add_vliw_inst(self.nop(), self.nop(), self.nop(), self.gen_b_sync(), "Safety Sync")

        # 3. Enable Compute Globally (T_ENC)
        # 此後 PE Array 保持 Enable，由資料觸發計算
        inst_enc = self.gen_t_enc(scale=scale, zero_point=zero_point)
        self.add_vliw_inst(self.nop(), self.nop(), self.nop(), inst_enc, f"Global Enable (Scale={scale})")
        
        # 確保 Enable 訊號傳遞到 Array
        self.add_vliw_inst(self.nop(), self.nop(), self.nop(), self.gen_b_sync(), "Enable Sync")


    def compile_compute_block_stream(self, mode_name, act_addr, wgt_addr, wb_addr, 
                                     act_len=10, wgt_len=100, thread_id=0, new_acc=True):
        """
        [Phase 2] 串流計算區塊：Output Stationary 資料流。
        不包含 T_ENC，純粹透過資料驅動。
        """
        mode_cfg = self.modes[mode_name]
        mode_val = mode_cfg["mode_bits"]
        # [AGU Mode Integration]
        agu_mode = mode_cfg.get("agu_mode", 0) 
        
        # 1. State Maintenance (T_SCM)
        # 如果是新的 Output Tile (new_acc=True)，則清除 Accumulator
        # 如果是 Partial Sum 累加 (new_acc=False)，則保留 Accumulator
        clr_acc = 1 if new_acc else 0
        inst_scm = self.gen_t_scm(mode=mode_val, clr_acc=clr_acc, act_src=0, wei_src=1)
        self.add_vliw_inst(self.nop(), self.nop(), self.nop(), inst_scm, f"State: ClrAcc={clr_acc}")
        
        self._insert_decode_delay()

        # 2. Feed Data (R_R) -> Triggers Compute automatically
        # Slot 0 (Low Bank) loads Act, Slot 1 (High Bank) loads Weight
        inst_act = self.gen_r_r(length=act_len, address=act_addr, thread_id=thread_id, mode=agu_mode)
        inst_wgt = self.gen_r_r(length=wgt_len, address=wgt_addr, thread_id=thread_id, mode=agu_mode)
        
        # VLIW: Slot3 | Slot2 | Slot1(WGT) | Slot0(ACT)
        self.add_vliw_inst(self.nop(), self.nop(), inst_wgt, inst_act, "Stream Data (Auto-Trigger)")

        # 3. Wait for Compute & AGU (B_SYNC)
        inst_sync = self.gen_b_sync(wait_tile=1, wait_agu0=1, wait_agu1=1)
        self.add_vliw_inst(self.nop(), self.nop(), self.nop(), inst_sync, "Wait Compute")

        # 4. Flush Results (T_WB Smart Flush)
        # 將 Output Stationary 的結果寫回 Memory
        wb_insts = self.gen_t_wb_smart_flush(wb_addr, pattern_prefix="ROW")
        for i, wb_inst in enumerate(wb_insts):
            self.add_vliw_inst(self.nop(), self.nop(), self.nop(), wb_inst, f"WB Row {i}")

        # 5. Pipeline Delay
        wb_depth = self.wb_stages.get("t_wb_pipeline_depth", 3)
        for _ in range(wb_depth):
            self.add_vliw_inst(self.nop(), self.nop(), self.nop(), self.nop(), "WB Wait")

    # =========================================================================
    # 資料處理 (Data Handling)
    # =========================================================================

    def pack_data_into_tiles(self, flat_data, height, width):
        """
        [Tensor Addressing] 將平坦矩陣 (H,W) 打包成 128-bit Tensor Tiles (4x4)
        """
        # 確保維度符合 4x4 Tile 要求
        if height % 4 != 0 or width % 4 != 0:
            raise ValueError(f"Dimensions ({height}x{width}) must be multiples of 4.")

        tiles = []
        data_matrix = np.array(flat_data, dtype=np.uint8).reshape(height, width)
        
        # 雙層迴圈遍歷每個 4x4 Block
        for r in range(0, height, 4):
            for c in range(0, width, 4):
                patch = data_matrix[r:r+4, c:c+4]
                packed_tile = 0
                
                # Sub-word 0 = Row 0, Sub-word 3 = Row 3
                for row in range(4):
                    row_val = 0
                    for col in range(4):
                        val = int(patch[row][col])
                        # Little Endian inside Row: Col 0 is LSB
                        row_val |= (val << (col * 8))
                    
                    # Pack 32-bit Row into 128-bit Tile
                    packed_tile |= (row_val << (row * 32))
                
                tiles.append(packed_tile)
        return tiles

    def export_tiled_mem(self, filename, flat_data, H, W):
        """匯出經過 Tiling 打包的資料檔"""
        packed_data = self.pack_data_into_tiles(flat_data, H, W)
        self._write_hex(filename, packed_data)

    def export_files(self, output_dir="output"):
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
        
        with open(f"{output_dir}/instruction.mem", "w") as f:
            for line in self.instructions:
                f.write(f"{line}\n")
        
        print(f"Compilation Successful. Files generated in '{output_dir}/'")

    def _write_hex(self, filename, data):
        with open(filename, "w") as f:
            # 128-bit (16 bytes) per line
            for i in range(len(data)):
                val = data[i]
                f.write(f"{val:032X}\n")

# =============================================================================
# 主程式執行範例 (Output Stationary Workflow)
# =============================================================================
if __name__ == "__main__":
    # 初始化
    compiler = DTCoreCompiler("dtcore_config.json")
    
    # 0. 系統同步
    compiler.add_vliw_inst(compiler.nop(), compiler.nop(), compiler.nop(), 
                           compiler.gen_b_sync(ext_wait=1), "Wait Ext DMA")

    # 1. 層級初始化 (Setup Layer)
    # 設定 Dense 模式並開啟 T_ENC，之後不需再開
    print("Initializing Layer: Dense 4x4...")
    compiler.compile_init_layer(mode_name="DENSE_4_4", scale=1)

    # 2. 串流計算 (Stream Processing) - 範例：計算兩個 Output Tiles
    # Output Tile 0: 需要 Act Addr 0, Wgt Addr 512
    print("Streaming Block 0...")
    compiler.compile_compute_block_stream(
        mode_name="DENSE_4_4",
        act_addr=0,
        wgt_addr=512,
        wb_addr=100,
        act_len=16,
        wgt_len=64,
        new_acc=True # 新的 Output，清空 Acc
    )

    # Output Tile 1: 需要 Act Addr 0 (Reuse!), Wgt Addr 576 (Next Filter)
    print("Streaming Block 1 (Input Reuse)...")
    compiler.compile_compute_block_stream(
        mode_name="DENSE_4_4",
        act_addr=0,   # Input Reuse
        wgt_addr=576, # Next Filter Bank
        wb_addr=101,  # Next Output Addr
        act_len=16,
        wgt_len=64,
        new_acc=True
    )
    
    # 3. 生成測試資料 (4x4 Tiling)
    dummy_act = [i % 255 for i in range(16*16)]
    dummy_wgt = [(i*2) % 255 for i in range(64*16)] # 較大的 Weight 資料
    
    compiler.export_tiled_mem("output/data_act.mem", dummy_act, 16, 16)
    compiler.export_tiled_mem("output/data_wgt.mem", dummy_wgt, 64, 16) # 64x16 Matrix
    
    compiler.export_files()