from DTCoreCompiler import DTCoreCompiler
import numpy as np
import os

def setup_compiler_for_gemm(mode_name="DENSE_4_4", scale=1):
    """輔助函式：初始化編譯器並設定 GEMM 層"""
    compiler = DTCoreCompiler("dtcore_config.json")
    # 系統同步與層級設定
    compiler.add_vliw_inst(compiler.nop(), compiler.nop(), compiler.nop(), 
                           compiler.gen_b_sync(ext_wait=1), "Wait Ext DMA")
    compiler.compile_init_layer(mode_name=mode_name, scale=scale)
    return compiler

def run_4x4_gemm_single_tile():
    """
    場景 1: 單一 4x4 矩陣乘法
    """
    print("\n[Gen] Generating 4x4 Matrix Multiplication...")
    compiler = setup_compiler_for_gemm()

    # 3. 定義位址 (Tile Index)
    # 假設 A 在 Low Bank Addr 0, B 在 High Bank Addr 0, 結果寫回 Addr 100
    ADDR_A = 0
    ADDR_B = 0
    ADDR_C = 100

    # 4. 生成計算區塊
    # 長度為 1 (代表 1 個 128-bit Tile)
    compiler.compile_compute_block_stream(
        mode_name="DENSE_4_4",
        act_addr=ADDR_A, 
        wgt_addr=ADDR_B, 
        wb_addr=ADDR_C,
        act_len=1,   # 讀取 1 個 Tile
        wgt_len=1,   # 讀取 1 個 Tile
        new_acc=True # 新的計算，清除 Accumulator
    )

    # 5. 匯出檔案
    # 產生 4x4 隨機資料
    data_a = [i for i in range(16)]       # 4x4 矩陣
    data_b = [1 for i in range(16)]       # Identity-like or simple
    
    output_dir = os.path.join("output", "gemm4x4")
    compiler.export_tiled_mem(os.path.join(output_dir, "data_act.mem"), data_a, 4, 4)
    compiler.export_tiled_mem(os.path.join(output_dir, "data_wgt.mem"), data_b, 4, 4)
    compiler.export_files(output_dir)


def run_8x8_gemm_blocked():
    """
    場景 2: 8x8 矩陣乘法 (Block GEMM)
    """
    print("\n[Gen] Generating 8x8 Matrix Multiplication...")
    compiler = setup_compiler_for_gemm()

    # 2. 定義 Tile 位址映射
    # 8x8 矩陣 = 4 個 Tiles (2x2 排列)
    # A Tiles: 0, 1 (Row 0), 2, 3 (Row 1)
    # B Tiles: 16, 17 (Row 0), 18, 19 (Row 1) (放在 High Bank offset 16)
    TILES_A = [[0, 1], [2, 3]]       # A[row][col]
    TILES_B = [[16, 17], [18, 19]]   # B[row][col]
    TILES_C = [[100, 101], [102, 103]] # C[row][col]

    # 3. 巢狀迴圈生成指令 (Output Stationary Dataflow)
    # 遍歷 C 的每一個 Tile (i, j)
    for i in range(2):      # Output Row
        for j in range(2):  # Output Col
            
            wb_addr = TILES_C[i][j]
            print(f"  > Scheduling Output Tile C[{i}][{j}] at Addr {wb_addr}...")

            # 遍歷 K 維度 (累加維度)
            for k in range(2):
                addr_a = TILES_A[i][k] # A 的第 i 列第 k 行
                addr_b = TILES_B[k][j] # B 的第 k 列第 j 行
                
                # 關鍵邏輯: 
                # 如果是 k=0 (第一步)，需要清除 Accumulator (new_acc=True)
                # 如果是 k>0 (累加步)，保留 Accumulator (new_acc=False)
                is_first_step = (k == 0)
                
                # 下一個指令的註解
                print(f"    - Step k={k}: A[{addr_a}] * B[{addr_b}] -> Acc (New={is_first_step})")

                compiler.compile_compute_block_stream(
                    mode_name="DENSE_4_4",
                    act_addr=addr_a,
                    wgt_addr=addr_b,
                    wb_addr=wb_addr, # 每次都傳入寫回位址，但通常硬體只在最後一步寫回(這裡簡化為每步寫回或最後覆蓋)
                    act_len=1,
                    wgt_len=1,
                    new_acc=is_first_step
                )
                
                # 注意：在真實硬體優化中，我們可能只在 k=1 (最後一步) 發送 T_WB
                # 但目前的 compile_compute_block_stream 包含了 T_WB
                # 由於 Output Stationary，中間寫回並不會破壞 Acc 的值，所以這樣寫也是安全的(只是多浪費頻寬)
                # 若要極致優化，需將 T_WB 拆離函式。

    # 4. 匯出檔案
    # 產生 8x8 資料 (Flattened)
    data_8x8_a = [i for i in range(64)] # 0~63
    data_8x8_b = [1 if i % 9 == 0 else 0 for i in range(64)] # Identity Matrix 8x8
    
    output_dir = os.path.join("output", "gemm8x8")
    compiler.export_tiled_mem(os.path.join(output_dir, "data_act.mem"), data_8x8_a, 8, 8)
    compiler.export_tiled_mem(os.path.join(output_dir, "data_wgt.mem"), data_8x8_b, 8, 8)
    compiler.export_files(output_dir)

if __name__ == "__main__":
    run_4x4_gemm_single_tile()
    run_8x8_gemm_blocked()