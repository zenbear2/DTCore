import json
import os
import numpy as np

class DTCoreCompiler:
    def __init__(self, config_path="dtcore_config.json"):
        self.instructions = []
        
        # Load Config
        loaded_config = {}
        paths_to_try = [config_path, "dtcore_config_temp.json"]
        
        for path in paths_to_try:
            if os.path.exists(path):
                print(f"[Compiler] Loading config from {path}")
                try:
                    with open(path, 'r') as f:
                        loaded_config = json.load(f)
                    break
                except Exception as e:
                    print(f"[Warning] Failed to load {path}: {e}")
        
        if not loaded_config:
            print(f"[Warning] No config file found. Using internal defaults.")
        
        self.config = loaded_config
        self.sys_info = self.config.get("system_info", {})
        
        # Initialize WB Patterns
        self.wb_patterns_cfg = self.config.get("wb_patterns", {})
        if not self.wb_patterns_cfg:
            for r in range(4):
                key = f"ROW_{r}"
                self.wb_patterns_cfg[key] = {"da_bus": [0,0,0,0], "reorder": [0,0,0,0]}

        # Opcode Definitions (6-bit Integers)
        self.OP_R_TWB  = 0b000000 
        self.OP_R_CW   = 0b001000 
        self.OP_R_R    = 0b010000 
        self.OP_B_S    = 0b011000 
        self.OP_T_SCM  = 0b100000 
        self.OP_T_ENC  = 0b101000 
        self.OP_C_OUT  = 0b101100 

        # B_SYNC Status Codes (Bits 13:8)
        self.STATUS_MANUAL      = 0x00
        self.STATUS_WB_DRAIN    = 0x01 
        self.STATUS_CONTEXT_BUSY= 0x02 
        self.STATUS_BLIND_SPOT  = 0x03 
        self.STATUS_RCW_DELAY   = 0x04 
        self.STATUS_SYNC_STALL  = 0x05 
        self.STATUS_BARRIER     = 0x06 
        self.STATUS_EXT_WAIT    = 0x07 
        self.STATUS_SCALE_GAP   = 0x08 

        # Load Compute Modes
        self.modes = self.config.get("compute_modes", {})
        
        # 1. Parsing Constraints
        try:
            self.hazards_cfg = self.config.get("hardware_constraints", {}).get("hazards", {})
            self.safety_cfg = self.config.get("timing_model", {}).get("safety", {})
            self.wb_cfg = self.config.get("timing_model", {}).get("writeback", {})
            self.routes_cfg = self.config.get("hardware_constraints", {}).get("interconnect", {}).get("valid_routes", {})
            
            self.wb_drain_cycles = self.wb_cfg.get("t_wb_pipeline_depth", 3) + \
                                   self.wb_cfg.get("pipeline_drain_safety_margin", 1)
        except:
            self.safety_cfg = {"requires_double_sync": False, "r_cw_post_sync_delay": 2}
            self.routes_cfg = {"0": [0], "1": [1], "2": [2], "3": [3]}
            self.wb_drain_cycles = 4

        # 2. Scoreboard
        # Structure: [4 Lanes][2 Contexts]
        self.context_busy_scoreboard = [[0, 0] for _ in range(4)]

        self.last_instr_was_bsync_ext = False
        self.cycles_since_bsync = 999
        self.cycles_since_twb = 999 
        self.cycles_since_tscm = 999
        self.last_rr_length = 0 

        self.is_t_enc_active = False
        self.current_scale = None        

    # =========================================================================
    # Low-Level Helpers
    # =========================================================================
    def make_inst(self, opcode, payload):
        return ((opcode & 0x3F) << 26) | (payload & 0x03FFFFFF)
    
    def _is_r_type(self, opcode):
        return (opcode >> 5) == 0

    def _get_opcode(self, inst):
        return (inst >> 26) & 0x3F

    def _get_stream_id(self, inst):
        return (inst >> 22) & 0x3

    def _map_stream_to_context(self, stream_id):
        if stream_id <= 1: return 0
        else: return 1

    # =========================================================================
    # Core Logic
    # =========================================================================
    def add_vliw_inst(self, s3, s2, s1, s0, comment=""):
        current_insts = [s0, s1, s2, s3]
        opcodes = [self._get_opcode(inst) for inst in current_insts]

        # ---------------------------------------------------------
        # Check 0: Routing
        # ---------------------------------------------------------
        for lane_idx, inst in enumerate(current_insts):
            if opcodes[lane_idx] == self.OP_R_TWB:
                src_tile = inst & 0x7 
                valid_srcs = self.routes_cfg.get(str(lane_idx), [])
                if src_tile not in valid_srcs:
                    pass 

        # ---------------------------------------------------------
        # Check 1: WB Drain
        # ---------------------------------------------------------
        has_active_r_type = False
        for inst in current_insts:
            op = self._get_opcode(inst)
            if self._is_r_type(op):
                # [Fix] 忽略狀態碼 [13:8]。只要沒有硬體等待旗標 [7:0]，就是安全的 NOP
                is_nop = (op == self.OP_B_S) and ((inst & 0xFF) == 0)
                if not is_nop:
                    has_active_r_type = True
                    break

        if has_active_r_type and self.cycles_since_twb < self.wb_drain_cycles:
            needed = self.wb_drain_cycles - self.cycles_since_twb
            for _ in range(needed): 
                self._emit_nop_cycle(self.STATUS_WB_DRAIN)

        # ---------------------------------------------------------
        # Check 2: AGU Context Busy (Target-Specific Check)
        # ---------------------------------------------------------
        # [Updated Rule] Only check if the TARGET context is busy.
        # It is safe to issue to Ctx 1 while Ctx 0 is running.
        
        COMPRESSION_THRESHOLD = 3 
        hazards_detected = {} 
        max_busy_cycles = 0

        for lane_idx, inst in enumerate(current_insts):
            op = opcodes[lane_idx]
            
            if op in [self.OP_R_R, self.OP_R_CW]:
                stream_id = self._get_stream_id(inst)
                target_ctx = self._map_stream_to_context(stream_id)
                
                # [Fix] Only check the specific target context
                busy_target = self.context_busy_scoreboard[lane_idx][target_ctx]

                if busy_target > 0:
                    hazards_detected[lane_idx] = target_ctx
                    if busy_target > max_busy_cycles:
                        max_busy_cycles = busy_target

        # Step 2: Handle Hazards
        if hazards_detected:
            if max_busy_cycles <= COMPRESSION_THRESHOLD:
                print(f"[Auto-Pad] Context Busy (Max {max_busy_cycles}): Inserting Check NOPs")
                for _ in range(max_busy_cycles): 
                    row = []
                    for lane in range(4):
                        if lane in hazards_detected:
                            ctx_to_wait = hazards_detected[lane]
                            row.append(self.gen_b_sync(wait_context=ctx_to_wait, status=self.STATUS_CONTEXT_BUSY))
                        else:
                            row.append(self.nop())
                    
                    self._emit_raw_inst(row[3], row[2], row[1], row[0], "Auto-Pad (Check Context)")
                    self._update_scoreboard(row, [self._get_opcode(x) for x in row])
            else:
                print(f"[Auto-Pad] Context Long Busy (Max {max_busy_cycles}): Using Smart Sync")
                self._emit_nop_cycle(self.STATUS_BLIND_SPOT)
                
                row = []
                for lane in range(4):
                    if lane in hazards_detected:
                        ctx_to_wait = hazards_detected[lane]
                        row.append(self.gen_b_sync(wait_context=ctx_to_wait, status=self.STATUS_SYNC_STALL))
                    else:
                        row.append(self.nop())
                
                self._emit_raw_inst(row[3], row[2], row[1], row[0], "Stall (Parallel Wait)")
                
                # [Fix] 快轉 Scoreboard 以模擬真實硬體的 Stall 時間。
                # 確保其他 Lanes 的計數器與全域 Pipeline 延遲 (如 cycles_since_twb) 同步推進
                stall_cycles = max_busy_cycles - 2 # 扣除已發射的 NOP 與 B_SYNC 各 1 週期
                if stall_cycles > 0:
                    for _ in range(stall_cycles):
                        self.cycles_since_twb += 1
                        self.cycles_since_tscm += 1
                        self.cycles_since_bsync += 1
                        for l in range(4):
                            ctx0_busy = self.context_busy_scoreboard[l][0] > 0
                            self.context_busy_scoreboard[l][0] = max(0, self.context_busy_scoreboard[l][0] - 1)
                            if not ctx0_busy:
                                self.context_busy_scoreboard[l][1] = max(0, self.context_busy_scoreboard[l][1] - 1)
                
                self._update_scoreboard(row, [self._get_opcode(x) for x in row])

        # ---------------------------------------------------------
        # Check 3: Tile Busy
        # ---------------------------------------------------------
        has_wait_tile = False
        for inst in current_insts:
            if self._get_opcode(inst) == self.OP_B_S:
                if (inst >> 7) & 1: has_wait_tile = True
        
        if has_wait_tile:
            try:
                constraints = self.safety_cfg['tile_busy_detection']['constraints']
                rule = constraints['single_data'] if self.last_rr_length == 0 else constraints['burst_data']
                req_gap = rule['required_gap_cycles']
            except:
                req_gap = 1

            if self.cycles_since_tscm < req_gap:
                needed = req_gap - self.cycles_since_tscm
                for _ in range(needed): 
                    self._emit_nop_cycle(self.STATUS_BLIND_SPOT)

        # ---------------------------------------------------------
        # Check 4: R_CW Safety Delay
        # ---------------------------------------------------------
        has_r_cw = any(op == self.OP_R_CW for op in opcodes)
        
        if has_r_cw and self.last_instr_was_bsync_ext:
            required_delay = self.safety_cfg.get("r_cw_post_sync_delay", 0)
            if self.cycles_since_bsync < required_delay:
                needed = required_delay - self.cycles_since_bsync
                print(f"[Auto-Pad] R_CW Safety Delay: Inserting {needed} NOPs")
                for _ in range(needed): 
                    self._emit_nop_cycle(self.STATUS_RCW_DELAY)

        # ================= Commit =================
        self._emit_raw_inst(s3, s2, s1, s0, comment)
        
        # ---------------------------------------------------------
        # Post-Commit: Double Sync Logic
        # ---------------------------------------------------------
        is_bsync_ext = False
        for inst in current_insts:
            if self._get_opcode(inst) == self.OP_B_S:
                if (inst >> 4) & 1: 
                    is_bsync_ext = True
                    break
        
        if is_bsync_ext:
            if self.safety_cfg.get("requires_double_sync", False) and not self.last_instr_was_bsync_ext:
                 print(f"[Auto-Pad] Double Sync Enforcement: Re-issuing B_SYNC")
                 self._emit_raw_inst(s3, s2, s1, s0, comment + " (Double Sync)")
                 self._update_scoreboard(current_insts, opcodes)

            self.last_instr_was_bsync_ext = True
            self.cycles_since_bsync = 0
        else:
            self.last_instr_was_bsync_ext = False
            self.cycles_since_bsync += 1                

        self._update_scoreboard(current_insts, opcodes)

    def _emit_nop_cycle(self, status=0):
        n = self.nop(status)
        self._emit_raw_inst(n, n, n, n, f"Auto-Pad (Status {status})")
        self._update_scoreboard([n]*4, [self.OP_B_S]*4)

    def _update_scoreboard(self, insts, opcodes):
        self.cycles_since_twb += 1
        self.cycles_since_tscm += 1
        
        # [Priority-Aware Counter Update]
        # Even though issuing is safe, we still need to track if Context 1 is actually making progress
        # to correctly predict WHEN it will finish.
        for lane in range(4):
            ctx0_busy = self.context_busy_scoreboard[lane][0] > 0
            
            # 1. High Priority (Context 0): Always decrements
            self.context_busy_scoreboard[lane][0] = max(0, self.context_busy_scoreboard[lane][0] - 1)
            
            # 2. Low Priority (Context 1): Only decrements if Ctx 0 is IDLE
            if not ctx0_busy:
                self.context_busy_scoreboard[lane][1] = max(0, self.context_busy_scoreboard[lane][1] - 1)
            # Else: Stalled by hardware, counter holds. This ensures we don't issue a NEW command
            # to Ctx 1 thinking it's done, when it's actually still pending.

        for lane_idx, op in enumerate(opcodes):
            if ((insts[lane_idx] >> 30) & 0x3) == 0x3: # T_WB
                self.cycles_since_twb = 0
            
            if op == self.OP_T_SCM:
                self.cycles_since_tscm = 0
            
            if op in [self.OP_R_R, self.OP_R_CW]:
                length = (insts[lane_idx] >> 10) & 0x3FF
                stream_id = self._get_stream_id(insts[lane_idx])
                target_ctx = self._map_stream_to_context(stream_id)
                
                # Set Busy for the target context
                self.context_busy_scoreboard[lane_idx][target_ctx] = length + 1
                
                if op == self.OP_R_R:
                    self.last_rr_length = length

    def _emit_raw_inst(self, slot3, slot2, slot1, slot0, comment=""):
        hex_str = f"{slot3:08X}{slot2:08X}{slot1:08X}{slot0:08X}"
        self.instructions.append(f"{hex_str} // {comment}")

    def nop(self, status=0):
        return self.gen_b_sync(status=status)

    def _pack_pattern_list(self, value_list):
        packed = 0
        for i, val in enumerate(value_list):
            shift = (3 - i) * 2
            packed |= (val & 0x3) << shift
        return packed

    # =========================================================================
    # Instruction Generators
    # =========================================================================
    def gen_r_cw(self, length, address, stream_id=0):
        hw_len = max(0, length - 1)
        payload = ((stream_id & 0x3) << 22) | ((hw_len & 0x3FF) << 10) | (address & 0x3FF)
        return self.make_inst(self.OP_R_CW, payload)

    def gen_r_r(self, length, address, stream_id=0, interval=0):
        hw_len = max(0, length - 1)
        payload = ((stream_id & 0x3) << 22) | ((interval & 0x3) << 20) | \
                  ((hw_len & 0x3FF) << 10) | (address & 0x3FF)
        return self.make_inst(self.OP_R_R, payload)
        
    def gen_b_sync(self, wait_tile=0, wait_context=None, ext_wait=0, sync_mask=0, status=0):
        t0_bit = 0
        t1_bit = 0
        
        if wait_context == 0:
            t0_bit = 1
        elif wait_context == 1:
            t1_bit = 1
        
        payload = ((status & 0x3F) << 8) | \
                  ((wait_tile & 1) << 7) | \
                  (t1_bit << 6) | \
                  (t0_bit << 5) | \
                  ((ext_wait & 1) << 4) | \
                  (sync_mask & 0xF)
                  
        return self.make_inst(self.OP_B_S, payload)

    def gen_t_scm(self, mode, relu=0, clr_acc=0, clr_out=0, wei_tid=0, wei_src=0, act_tid=0, act_src=0):
        payload = ((clr_out & 1) << 16) | ((clr_acc & 1) << 15) | ((relu & 1) << 14) | \
                  ((mode & 0xF) << 10) | ((wei_tid & 0x3) << 8) | ((wei_src & 0x7) << 5) | \
                  ((act_tid & 0x3) << 3) | (act_src & 0x7)
        return self.make_inst(self.OP_T_SCM, payload)
    
    def gen_t_enc(self, scale, zero_point=0):
        payload = ((zero_point & 0xFF) << 16) | (scale & 0x7FFF)
        return self.make_inst(self.OP_T_ENC, payload)

    def gen_r_twb(self, source_tile_id):
        sel = source_tile_id & 0x7
        payload = (sel << 9) | (sel << 6) | (sel << 3) | sel
        return self.make_inst(self.OP_R_TWB, payload)
        
    def gen_t_wb(self, wb_addr, mask, dabus_sel, reorder):
        payload = ((mask & 0xF) << 26) | ((dabus_sel & 0xFF) << 18) | \
                  ((reorder & 0xFF) << 10) | (wb_addr & 0x3FF)
        inst = (0x3 << 30) | (payload & 0x3FFFFFFF)
        return inst

    def _get_mode_bits(self, mode_name):
        return self.modes.get(mode_name, {}).get("mode_bits", 0)

    def _get_agu_interval(self, mode_name):
        cfg = self.modes.get(mode_name, {})
        return cfg.get("agu_interval", cfg.get("agu_mode", 0))

    # =========================================================================
    # High-Level Flows
    # =========================================================================
    def compile_init_layer(self, mode_name, scale=1, zero_point=0):
        tile_mode_bits = self._get_mode_bits(mode_name)
        inst_scm = self.gen_t_scm(mode=tile_mode_bits, clr_acc=1, clr_out=1, act_src=0, wei_src=0)
        self.add_vliw_inst(inst_scm, inst_scm, inst_scm, inst_scm, f"Init Mode: {mode_name}")

        need_enc = False
        if not self.is_t_enc_active:
            need_enc = True
        elif self.current_scale != scale:
            need_enc = True
            
        if need_enc:
            inst_enc = self.gen_t_enc(scale=scale, zero_point=zero_point)
            self.add_vliw_inst(inst_enc, inst_enc, inst_enc, inst_enc, f"Global Enable (Scale={scale})")
            inst_sync = self.gen_b_sync(sync_mask=0xF, status=self.STATUS_BARRIER)
            self.add_vliw_inst(inst_sync, inst_sync, inst_sync, inst_sync, "Enable Sync (Global Barrier)")
            self.is_t_enc_active = True
            self.current_scale = scale

    def _emit_scale_stage(self):
        scale_mode_bits = self._get_mode_bits("SCALE")
        inst_scale = self.gen_t_scm(mode=scale_mode_bits, clr_acc=0, clr_out=0)
        self.add_vliw_inst(inst_scale, inst_scale, inst_scale, inst_scale, "Post-Process: Switch to SCALE Mode")
        
        print("  [Smart Sync] Scale Mode: Using 1 NOP + Wait Tile Optimization")
        n = self.nop(self.STATUS_SCALE_GAP)
        self.add_vliw_inst(n, n, n, n, "Gap NOP (Blind Spot)")
        
        sync = self.gen_b_sync(wait_tile=1, sync_mask=0xF, status=self.STATUS_SYNC_STALL)
        self.add_vliw_inst(sync, sync, sync, sync, "Sync (Wait Scale)")

    def gen_t_wb_packed_flush(self, target_addr):
        insts = []
        for i in range(4): 
            mask = 1 << i
            key = f"ROW_{i}"
            cfg = self.wb_patterns_cfg.get(key, {"da_bus":[0]*4, "reorder":[0]*4})
            da_val = self._pack_pattern_list(cfg["da_bus"])
            re_val = self._pack_pattern_list(cfg["reorder"])
            insts.append(self.gen_t_wb(target_addr, mask=mask, dabus_sel=da_val, reorder=re_val))
        return insts

    def compile_gemm_conflict_free(self, act_L, act_H, wgt_L, wgt_H, wb_base):
        print("  [Compiler] Mode: Conflict-Free Parallel (Smart Issue)")
        self._emit_compute_sequence(act_L, act_H, wgt_L, wgt_H, "DENSE_4_4")
        self._emit_scale_stage()

        inst_s0 = self.gen_r_twb(0)
        inst_s1 = self.gen_r_twb(1)
        inst_s2 = self.gen_r_twb(2)
        inst_s3 = self.gen_r_twb(3)
        self.add_vliw_inst(inst_s3, inst_s2, inst_s1, inst_s0, "WB Route: Parallel Setup")

        wb_t0 = self.gen_t_wb_packed_flush(wb_base)
        wb_t1 = self.gen_t_wb_packed_flush(wb_base + 1)
        wb_t2 = self.gen_t_wb_packed_flush(wb_base + 2)
        wb_t3 = self.gen_t_wb_packed_flush(wb_base + 3)

        for i in range(4):
            self.add_vliw_inst(wb_t3[i], wb_t2[i], wb_t1[i], wb_t0[i], f"Parallel WB {i}")
        
    def compile_gemm_bank_conflict(self, act_L, act_H, wgt_L, wgt_H, wb_base):
        print("  [Compiler] Mode: Bank Conflict (Smart Issue)")
        self._emit_compute_sequence(act_L, act_H, wgt_L, wgt_H, "DENSE_4_4")
        self._emit_scale_stage()

        nop = self.nop()
        inst_s0_p1 = self.gen_r_twb(0)
        inst_s2_p1 = self.gen_r_twb(2)
        self.add_vliw_inst(nop, inst_s2_p1, nop, inst_s0_p1, "WB Phase 1 Setup")

        wb_t0 = self.gen_t_wb_packed_flush(wb_base + 0) 
        wb_t2 = self.gen_t_wb_packed_flush(wb_base + 0)
        for i in range(4):
            self.add_vliw_inst(nop, wb_t2[i], nop, wb_t0[i], f"Phase 1 Exec {i}")

        inst_s0_p2 = self.gen_r_twb(1) 
        inst_s2_p2 = self.gen_r_twb(3) 
        self.add_vliw_inst(nop, inst_s2_p2, nop, inst_s0_p2, "WB Phase 2 Switch")

        wb_t1 = self.gen_t_wb_packed_flush(wb_base + 1) 
        wb_t3 = self.gen_t_wb_packed_flush(wb_base + 1) 

        for i in range(4):
            self.add_vliw_inst(nop, wb_t3[i], nop, wb_t1[i], f"Phase 2 Exec {i}")

    def _emit_compute_sequence(self, aL, aH, wL, wH, mode_name):
        tile_mode_bits = self._get_mode_bits(mode_name)
        agu_interval = self._get_agu_interval(mode_name)
        
        scm_t0 = self.gen_t_scm(mode=tile_mode_bits, clr_acc=1, act_src=0, wei_src=0)
        scm_t1 = self.gen_t_scm(mode=tile_mode_bits, clr_acc=1, act_src=1, wei_src=0)
        scm_t2 = self.gen_t_scm(mode=tile_mode_bits, clr_acc=1, act_src=0, wei_src=1)
        scm_t3 = self.gen_t_scm(mode=tile_mode_bits, clr_acc=1, act_src=1, wei_src=1)
        self.add_vliw_inst(scm_t3, scm_t2, scm_t1, scm_t0, "Config Tiles (Independent)")
        
        DATA_LEN = 2 
        SHORT_DATA_THRESHOLD = 2
        
        rr_0 = self.gen_r_r(length=DATA_LEN, address=aL, stream_id=0, interval=agu_interval)
        rr_1 = self.gen_r_r(length=DATA_LEN, address=aH, stream_id=0, interval=agu_interval)
        rr_2 = self.gen_r_r(length=DATA_LEN, address=wL, stream_id=0, interval=agu_interval)
        rr_3 = self.gen_r_r(length=DATA_LEN, address=wH, stream_id=0, interval=agu_interval)
        self.add_vliw_inst(rr_3, rr_2, rr_1, rr_0, f"Stream Data (Len={DATA_LEN}, Int={agu_interval})")
        
        if DATA_LEN <= SHORT_DATA_THRESHOLD:
            print(f"  [Smart Sync] Short Data (Len={DATA_LEN}): Using 2 NOPs + Wait Tile")
            n = self.nop(self.STATUS_BLIND_SPOT)
            self.add_vliw_inst(n, n, n, n, "Gap NOP 1")
            self.add_vliw_inst(n, n, n, n, "Gap NOP 2")
            
            sync = self.gen_b_sync(wait_tile=1, wait_context=None, sync_mask=0xF, status=self.STATUS_SYNC_STALL)
            self.add_vliw_inst(sync, sync, sync, sync, "Sync (Wait Tile + Barrier)")
        else:
            print(f"  [Smart Sync] Long Data (Len={DATA_LEN}): Using 1 NOP + Local Wait + Barrier")
            n = self.nop(self.STATUS_BLIND_SPOT)
            self.add_vliw_inst(n, n, n, n, "Gap NOP 1")
            
            sync_all = self.gen_b_sync(wait_tile=1, wait_context=0, sync_mask=0xF, status=self.STATUS_SYNC_STALL)
            self.add_vliw_inst(sync_all, sync_all, sync_all, sync_all, "Sync (Local Wait Ctx0 + Global Barrier)")

    def export_files(self, output_dir="output"):
        if not os.path.exists(output_dir): os.makedirs(output_dir)
        with open(f"{output_dir}/instruction.mem", "w") as f:
            for line in self.instructions: f.write(f"{line}\n")
    
    def export_tiled_mem(self, filename, flat_data, H, W):
        if not os.path.exists(os.path.dirname(filename)): os.makedirs(os.path.dirname(filename))
        with open(filename, "w") as f:
            arr = np.array(flat_data).reshape(H, W)
            for r in range(0, H, 4):
                for c in range(0, W, 4):
                    patch = arr[r:r+4, c:c+4]
                    packed = 0
                    for tr in range(4):
                        row_val = 0
                        for tc in range(4):
                            val = int(patch[tr][tc]) & 0xFF
                            row_val |= (val << (tc*8))
                        packed |= (row_val << (tr*32))
                    f.write(f"{packed:032X}\n")