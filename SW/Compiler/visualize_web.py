import plotly.graph_objects as go
import os

class InstructionDecoder:
    """
    深度解碼器：將機器碼解析為詳細的人類可讀資訊
    修正歷程：
    1. 修正 Opcode 0x00 為 R_TWB (Setup)。
    2. 新增 R_TWB 的 Source Select 解析邏輯。
    3. [本次修正] 移除 '0 == NOP' 的判斷，0x00000000 為有效的 R_TWB 指令。
    """
    def __init__(self):
        # Opcode 定義
        self.OP_MAP = {
            # 依據 PDF Page 2，Opcode 0x00 為 R_TWB (Setup)
            0b000000: "R_TWB",  # 0x00 Tile Write-back Setup
            0b001000: "R_CW",   # 0x08 Core Write
            0b010000: "R_R",    # 0x10 Read / AGU Start
            0b011000: "B_SYNC", # 0x18 Barrier Sync
            0b100000: "T_SCM",  # 0x20 Tile SCM (Config)
            0b101000: "T_ENC",  # 0x28 Tile Enable Compute
            0b101100: "C_OUT",  # 0x2C Core Output
        }
        self.OP_T_WB_TOP = 0b11 # T_WB (Action) 使用高位元 11xxxx 識別

        # 模式對照表
        self.MODE_MAP = {
            0: "SPARSE_1_4",
            4: "SPARSE_2_4",
            8: "SPARSE_3_4",
            12: "DENSE_4_4",
            1: "SIMD",
            14: "SCALE"
        }

    def decode_32bit(self, val):
        # [修正] 移除 val == 0 的 NOP 判斷
        # 0x00000000 對應 Opcode 0 (R_TWB) 且 Payload 0，為有效指令
        
        # 1. Special Case: T_WB (Top 2 bits = 11)
        if ((val >> 30) & 0x3) == self.OP_T_WB_TOP:
            mask = (val >> 26) & 0xF
            dabus = (val >> 18) & 0xFF
            reorder = (val >> 10) & 0xFF
            wb_addr = val & 0x3FF
            
            desc = (f"<b>Addr:</b> {wb_addr}<br>"
                    f"<b>Mask:</b> {mask:04b}<br>"
                    f"<b>DA:</b> 0x{dabus:02X} <b>Re:</b> 0x{reorder:02X}")
            return "T_WB", desc

        # 2. Standard Opcode Decoding
        opcode = (val >> 26) & 0x3F
        payload = val & 0x03FFFFFF
        op_name = self.OP_MAP.get(opcode, f"UNK_{opcode:02X}")
        
        details = ""
        
        # 3. Deep Decode based on Opcode
        if op_name == "R_TWB":
            # R_TWB 解析邏輯
            # Payload Bits [11:0]: Source_Select (4組 3-bit 選擇信號)
            src_select = payload & 0xFFF
            
            # 3-bit 分組順序 (S3..S0)
            sel_3 = (src_select >> 9) & 0x7 
            sel_2 = (src_select >> 6) & 0x7 
            sel_1 = (src_select >> 3) & 0x7 
            sel_0 = (src_select) & 0x7      
            
            details = (f"<b>SrcSel:</b> 0x{src_select:03X}<br>"
                       f"Sub-BRAM3: Tile{sel_3}<br>"
                       f"Sub-BRAM2: Tile{sel_2}<br>"
                       f"Sub-BRAM1: Tile{sel_1}<br>"
                       f"Sub-BRAM0: Tile{sel_0}")

        elif op_name == "R_R":
            thread_id = (payload >> 22) & 0x3
            agu_mode = (payload >> 20) & 0x3
            length = (payload >> 10) & 0x3FF
            addr = payload & 0x3FF
            details = (f"<b>Addr:</b> {addr}<br>"
                       f"<b>Len:</b> {length}<br>"
                       f"<b>TID:</b> {thread_id} <b>Mode:</b> {agu_mode}")

        elif op_name == "R_CW":
            thread_id = (payload >> 22) & 0x3
            length    = (payload >> 10) & 0x3FF 
            addr      = payload & 0x3FF         
            
            details = (f"<b>Addr:</b> {addr}<br>"
                       f"<b>Len:</b> {length}<br>"
                       f"<b>TID:</b> {thread_id}")
    
        elif op_name == "T_ENC":
            zero_point = (payload >> 16) & 0xFF
            scale = payload & 0xFFFF
            details = (f"<b>Scale:</b> {scale}<br>"
                       f"<b>ZP:</b> {zero_point}")
                       
        elif op_name == "B_SYNC":
            # 純 B_SYNC Opcode 且 Payload 為 0 可能仍被視為 NOP，視您的需求而定
            # 若您的架構中 B_SYNC(0) 等同 NOP，可保留此行；若不是，請刪除。
            # 目前保留此行以過濾純等待指令，避免混淆視聽。
            if val == ((0x18 << 26)): return None, "NOP" 
            
            wait_tile = (payload >> 7) & 1
            wait_agu1 = (payload >> 6) & 1
            wait_agu0 = (payload >> 5) & 1
            ext_wait  = (payload >> 4) & 1
            sync_mask = payload & 0xF
            
            waits = []
            if wait_tile: waits.append("Tile")
            if wait_agu0: waits.append("AGU0")
            if wait_agu1: waits.append("AGU1")
            if ext_wait:  waits.append("Ext")
            
            if sync_mask > 0:
                mask_list = []
                for i in range(4):
                    if (sync_mask >> i) & 1:
                        mask_list.append(f"S{i}")
                waits.append(f"WaitSlots:[{','.join(mask_list)}]")

            details = "<b>Wait:</b> " + (", ".join(waits) if waits else "None")
            
        elif op_name == "T_SCM":
            clr_out = (payload >> 16) & 1
            clr_acc = (payload >> 15) & 1
            relu    = (payload >> 14) & 1
            mode    = (payload >> 10) & 0xF
            wei_src = (payload >> 5) & 0x7
            act_src = payload & 0x7
            
            mode_str = self.MODE_MAP.get(mode, f"Unk({mode})")
            
            state_info = []
            if clr_acc: state_info.append("<span style='color:red'>CLR_ACC</span>")
            else:       state_info.append("<span style='color:green'>ACCUM</span>")
            
            if clr_out: state_info.append("CLR_OUT")
            if relu:    state_info.append("RELU")
            
            details = (f"<b>{mode_str}</b><br>"
                       f"{' '.join(state_info)}<br>"
                       f"Src: A={act_src}, W={wei_src}")

        return op_name, details

    def parse_mem_file(self, filepath):
        if not os.path.exists(filepath):
            print(f"Error: {filepath} not found.")
            return []
        timeline = []
        with open(filepath, 'r') as f:
            for line in f:
                line = line.split("//")[0].strip()
                if not line: continue
                try:
                    full_int = int(line, 16)
                    slots = []
                    for i in range(4):
                        slot_val = (full_int >> (i * 32)) & 0xFFFFFFFF
                        slots.append(self.decode_32bit(slot_val))
                    timeline.append(slots)
                except ValueError:
                    continue
        return timeline

def visualize_interactive_detailed(timeline, output_file="schedule_detailed.html"):
    if not timeline: return

    # 1. 準備資料
    cycles, slots, op_names, hover_texts, colors = [], [], [], [], []

    # 顏色定義
    color_map = {
        "R_R":    "#00CC96", # Green
        "R_TWB":  "#FFA15A", # Orange (Setup)
        "T_WB":   "#EF553B", # Red (Action)
        "T_ENC":  "#AB63FA", # Purple
        "T_SCM":  "#636EFA", # Blue
        "B_SYNC": "#FECB52", # Yellow
        "NOP":    "#E5E5E5", # Gray
        "R_CW":   "#00D2FC", # Cyan
        "C_OUT":  "#FF97FF", # Pink
    }

    for c_idx, cycle_slots in enumerate(timeline):
        for s_idx, (name, desc) in enumerate(cycle_slots):
            if name is None: continue 
            
            cycles.append(c_idx)
            slots.append(f"Slot {s_idx}")
            
            # 簡稱設定
            display_text = name
            if name == "T_SCM": display_text = "CFG"
            if name == "B_SYNC": display_text = "SYNC"
            # R_TWB 若出現頻率高，可考慮使用 "T_SET" 等更短名稱
            
            op_names.append(display_text)
            
            # Hover Info
            hover_info = (f"<b style='font-size:14px'>Cycle {c_idx} | Slot {s_idx}</b><br>"
                          f"<span style='color:{color_map.get(name, 'black')}'><b>{name}</b></span><br>"
                          f"<br>{desc}")
            hover_texts.append(hover_info)
            
            colors.append(color_map.get(name, "#333333"))

    # 2. 建立圖表
    fig = go.Figure()

    fig.add_trace(go.Scatter(
        x=cycles,
        y=slots,
        text=op_names,
        mode="markers+text",
        marker=dict(
            symbol="square",
            size=45, 
            color=colors,
            line=dict(width=1, color="white")
        ),
        hovertemplate="%{hovertext}<extra></extra>",
        hovertext=hover_texts,
        textposition="middle center",
        textfont=dict(size=10, color="black")
    ))

    # 3. 調整版面
    num_cycles = len(timeline)
    fig.update_layout(
        title=f"DTCore Detailed Schedule Explorer ({num_cycles} Cycles)",
        xaxis=dict(
            title="Time (Cycles)",
            tickmode="linear",
            dtick=1,
            gridcolor="#E0E0E0",
            rangeslider=dict(visible=True),
            showgrid=True
        ),
        yaxis=dict(
            title="VLIW Slots",
            categoryarray=["Slot 0", "Slot 1", "Slot 2", "Slot 3"],
            gridcolor="#E0E0E0",
            showgrid=True
        ),
        plot_bgcolor="white",
        height=650,
        hoverlabel=dict(
            bgcolor="white",
            font_size=12,
            font_family="Consolas, monospace"
        )
    )

    print(f"Generating detailed chart: {output_file}")
    fig.write_html(output_file)
    print("Open the HTML file to inspect details.")

if __name__ == "__main__":
    decoder = InstructionDecoder()
    
    # 請依實際情況修改路徑
    mem_file = "output/gemm8x8_parallel/instruction.mem" 
    
    print(f"Reading {mem_file}...")
    data = decoder.parse_mem_file(mem_file)
    visualize_interactive_detailed(data)