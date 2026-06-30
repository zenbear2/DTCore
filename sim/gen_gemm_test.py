import os
import numpy as np
from DTCoreCompiler import DTCoreCompiler

class GEMM_DataGenerator:
    def __init__(self, data_len_blocks=2):
        """
        初始化資料生成器
        data_len_blocks: 對應 Compiler R_R 指令的 length (即傳輸多少個 4-element 向量)
        """
        self.block_size = 4
        self.M = 4 # Tile 固定高度
        self.N = 4 # Tile 固定寬度
        # K 維度 = 傳輸長度 * 4 (因為每個 Cycle 傳輸 4 個元素)
        self.K = data_len_blocks * 4 
        
        print(f"[DataGen] Configured for GEMM: M={self.M}, N={self.N}, K={self.K}")

    def generate_inputs(self):
        # 1. 產生隨機 INT8/INT32 資料 (-10 ~ 10 避免溢位太快)
        # Act: (M, K)
        self.act_l = np.random.randint(-10, 10, (self.M, self.K)).astype(np.int32)
        self.act_h = np.random.randint(-10, 10, (self.M, self.K)).astype(np.int32)
        
        # Wgt: (K, N)
        # 注意: 硬體通常是以 Column-Major 或 Block 格式儲存，這裡我們用標準矩陣格式模擬
        self.wgt_l = np.random.randint(-10, 10, (self.K, self.N)).astype(np.int32)
        self.wgt_h = np.random.randint(-10, 10, (self.K, self.N)).astype(np.int32)
        
        return self.act_l, self.act_h, self.wgt_l, self.wgt_h

    def compute_golden(self):
        # 2. 計算黃金對照組 (Golden Reference)
        # 模擬 DTCore 內部的 4-Way 平行運算邏輯
        
        # Tile 0: Act_L * Wgt_L
        self.golden_t0 = np.dot(self.act_l, self.wgt_l)
        
        # Tile 1: Act_H * Wgt_L
        self.golden_t1 = np.dot(self.act_h, self.wgt_l)
        
        # Tile 2: Act_L * Wgt_H
        self.golden_t2 = np.dot(self.act_l, self.wgt_h)
        
        # Tile 3: Act_H * Wgt_H
        self.golden_t3 = np.dot(self.act_h, self.wgt_h)
        
        return self.golden_t0, self.golden_t1, self.golden_t2, self.golden_t3

    def export_data(self, compiler, output_dir):
        if not os.path.exists(output_dir): os.makedirs(output_dir)
        
        print(f"[DataGen] Exporting Input Tensors to {output_dir}...")
        # 匯出輸入資料 (給 Testbench 的 Memory Loader 使用)
        compiler.export_tiled_mem(f"{output_dir}/input_act_L.mem", self.act_l.flatten(), self.M, self.K)
        compiler.export_tiled_mem(f"{output_dir}/input_act_H.mem", self.act_h.flatten(), self.M, self.K)
        compiler.export_tiled_mem(f"{output_dir}/input_wgt_L.mem", self.wgt_l.flatten(), self.K, self.N)
        compiler.export_tiled_mem(f"{output_dir}/input_wgt_H.mem", self.wgt_h.flatten(), self.K, self.N)
        
        print(f"[DataGen] Exporting Golden Outputs to {output_dir}...")
        # 匯出預期結果 (給 Testbench 比對 WB_RAM 使用)
        compiler.export_tiled_mem(f"{output_dir}/golden_tile0.mem", self.golden_t0.flatten(), self.M, self.N)
        compiler.export_tiled_mem(f"{output_dir}/golden_tile1.mem", self.golden_t1.flatten(), self.M, self.N)
        compiler.export_tiled_mem(f"{output_dir}/golden_tile2.mem", self.golden_t2.flatten(), self.M, self.N)
        compiler.export_tiled_mem(f"{output_dir}/golden_tile3.mem", self.golden_t3.flatten(), self.M, self.N)

def main():
    print("==========================================================")
    print("      DTCore VLIW Compiler - Testbench Gen (Data + Instr)")
    print("==========================================================")

    # 1. 初始化
    compiler = DTCoreCompiler("dtcore_config.json")
    output_dir = "output_verification"
    
    # -------------------------------------------------------------
    # Step 1: 產生測試資料 (Data Generation)
    # -------------------------------------------------------------
    # 設定 DATA_LEN = 2 (對應指令中的 length 參數)
    # 代表 K 維度深度為 8 (2 * 4)
    gen = GEMM_DataGenerator(data_len_blocks=2) 
    
    act_l, act_h, wgt_l, wgt_h = gen.generate_inputs()
    golden = gen.compute_golden()
    gen.export_data(compiler, output_dir)
    
    # -------------------------------------------------------------
    # Step 2: 定義 RegFile 位址
    # -------------------------------------------------------------
    RF_ADDR_ACT_L = 0x000 
    RF_ADDR_ACT_H = 0x000 # Act High Bank Base
    RF_ADDR_WGT_L = 0x200 
    RF_ADDR_WGT_H = 0x200 # Wgt High Bank Base
    RF_ADDR_WB    = 0x300 # Writeback Base

    # -------------------------------------------------------------
    # Step 3: 生成指令碼 (Code Generation)
    # -------------------------------------------------------------
    print("\n[Compiler] Generating Instructions...")

    # [Phase 1] System Initialization
    # 初始化 Tile 為 DENSE_4_4 模式，並設定 Scale
    compiler.compile_init_layer(mode_name="DENSE_4_4", scale=0x7FFF)

    # [Phase 2] Load Data (R_CW)
    # 等待外部訊號 (模擬 DMA Ready)
    sync_ext = compiler.gen_b_sync(ext_wait=1, sync_mask=0xF, status=compiler.STATUS_EXT_WAIT)
    compiler.add_vliw_inst(sync_ext, sync_ext, sync_ext, sync_ext, "Pre-Load Sync (Wait External)")

    # 發射載入指令
    # [Best Practice] 全部使用 stream_id=0 (Context 0 - High Priority)
    LOAD_LEN = 2
    rcw_0 = compiler.gen_r_cw(length=LOAD_LEN, address=RF_ADDR_ACT_L, stream_id=0) # Lane 0
    rcw_1 = compiler.gen_r_cw(length=LOAD_LEN, address=RF_ADDR_ACT_H, stream_id=0) # Lane 1
    rcw_2 = compiler.gen_r_cw(length=LOAD_LEN, address=RF_ADDR_WGT_L, stream_id=0) # Lane 2
    rcw_3 = compiler.gen_r_cw(length=LOAD_LEN, address=RF_ADDR_WGT_H, stream_id=0) # Lane 3
    
    # 編譯器會自動偵測 Ext_Wait -> R_CW 的安全依賴，並插入 Safety NOPs
    compiler.add_vliw_inst(rcw_3, rcw_2, rcw_1, rcw_0, "Load Input Data (R_CW)")

    # [Phase 3] Compute (R_R)
    # 使用 gen_gemm_conflict_free 函式，它會自動發射 R_R 並處理等待 (Stall)
    # 因為 R_CW 剛發射，AGU Context 忙碌，編譯器會自動插入 B_SYNC
    compiler.compile_gemm_conflict_free(
        act_L=RF_ADDR_ACT_L, 
        act_H=RF_ADDR_ACT_H, 
        wgt_L=RF_ADDR_WGT_L, 
        wgt_H=RF_ADDR_WGT_H, 
        wb_base=RF_ADDR_WB
    )

    # -------------------------------------------------------------
    # Step 4: 輸出指令檔
    # -------------------------------------------------------------
    print(f"\n[Info] Exporting instructions to {output_dir}/instruction.mem ...")
    compiler.export_files(output_dir)
    print("[Done] Verification Test Generated.")

if __name__ == "__main__":
    main()