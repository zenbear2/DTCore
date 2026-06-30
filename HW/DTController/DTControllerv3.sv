// Version B1 - Optimized with FetchDecodeUnit & Skid Buffer
// Integrates 4-way Parallel Fetch & Decode Pipeline
module DTControllerv3(
    input  wire clk,
    input  wire rst_n,

    // Instruction Interface (from IFB/SkidBuffer)
    input  wire [127:0] i_inst,
    input  wire [3:0]   i_inst_valid, // Corresponds to i_fifo_valid
    input  wire [3:0]   i_inst_empty,


    // External Status & Busy Signals
    input  wire         i_ext_busy,
    input  wire [1:0]   i_agu_slot_ready_bus [3:0],
    input  wire [3:0]   i_agu_ready_bus, 
    input  wire [3:0]   i_tile_busy_bus,

    // Tile State Outputs
    output wire [3:0]   o_tile_enable,
    output wire [3:0]   o_tile_mode [3:0],
    output wire [3:0]   o_tile_relu,
    output wire [3:0]   o_tile_clear_acc,
    output wire [3:0]   o_tile_clear_out,
    output wire [0:0]   o_tile_act_select [3:0],
    output wire [0:0]   o_tile_weight_select [3:0],
    output wire [1:0]   o_tile_act_thread_id [3:0],
    output wire [1:0]   o_tile_weight_thread_id [3:0],
    output wire [15:0]  o_tile_scale [3:0],
    output wire [7:0]   o_tile_zero_point [3:0],

    // Tile WB Outputs
    output wire [7:0]   o_tile_dabus [3:0],
    output wire [3:0]   o_tile_dabus_valid,
    output wire [7:0]   o_tile_reorder [3:0],
    output wire [3:0]   o_tile_reorder_valid,
    output wire [9:0]   o_tile_wb_address [3:0],
    output wire [3:0]   o_tile_wb_address_valid,
    output wire [3:0]   o_tile_wb_mask [3:0],
    output wire [3:0]   o_tilewb_fifo_full,
    output wire [3:0]   o_error_tile_wb_conflict,
    output wire [3:0]   o_error_op,

    // RFBPCtrl Outputs
    output wire [9:0]   o_agu_addr [3:0],
    output wire [9:0]   o_agu_len [3:0],
    output wire [3:0]   o_agu_start,
    output wire [1:0]   o_agu_mode [3:0],
    output wire [1:0]   o_agu_thread_id [3:0],
    output wire [3:0]   o_agu_read,
    output wire [3:0]   o_agu_write,
    output wire [11:0]  o_rfbp_sel [3:0],
    output wire [3:0]   o_rfbp_wen,

    // Core Output Ctrl Outputs
    output wire [1:0]   o_core_output_thread_id [3:0],
    output wire [1:0]   o_core_output_select [3:0],
    output wire [3:0]   o_core_output_select_valid,

    // Instruction Fetch Control Signals
    output wire [3:0]   o_core_busy_bus,
    output wire [5:0]   o_status_bus [3:0],
    output wire [3:0]   o_fetch // Now drives the IFB Read Enable
);

    localparam SUB_INST_NUM = 4;
    // ====================================================================
    // Internal Wires for Pipeline Registers (Output of FetchDecodeUnit)
    // ====================================================================
    
    // Valid/Ready Signals
    wire [SUB_INST_NUM-1:0] fdu_fifo_rd_en;
    wire [SUB_INST_NUM-1:0] barrier_fetch_enable; // From Barrier to stall FDU

    // Decoded Control Ops
    wire [SUB_INST_NUM-1:0] pipe_regfile_tile_wb_op;
    wire [SUB_INST_NUM-1:0] pipe_regfile_core_in_op;
    wire [SUB_INST_NUM-1:0] pipe_regfile_read_op;
    wire [SUB_INST_NUM-1:0] pipe_block_sync_op;
    wire [SUB_INST_NUM-1:0] pipe_tile_mode_op;
    wire [SUB_INST_NUM-1:0] pipe_tile_en_op;
    wire [SUB_INST_NUM-1:0] pipe_tile_wb_op;
    wire [SUB_INST_NUM-1:0] pipe_core_out_op;
    wire [SUB_INST_NUM-1:0] pipe_error_op;

    // Parsed Data Fields (Arrays)
    wire [5:0]  pipe_opcode     [SUB_INST_NUM-1:0];
    
    // RFBPCtrl Fields
    wire [11:0] pipe_rf_src_sel [SUB_INST_NUM-1:0];
    wire [9:0]  pipe_addr       [SUB_INST_NUM-1:0];
    wire [9:0]  pipe_len        [SUB_INST_NUM-1:0];
    wire [1:0]  pipe_agu_mode   [SUB_INST_NUM-1:0];
    wire [1:0]  pipe_thread_id  [SUB_INST_NUM-1:0];

    // Core Output Fields
    wire [1:0]  pipe_core_out_sel   [SUB_INST_NUM-1:0];
    wire        pipe_core_out_valid [SUB_INST_NUM-1:0];
    wire [1:0]  pipe_core_out_tid   [SUB_INST_NUM-1:0];

    // Tile State Fields
    wire        pipe_tile_act_sel [SUB_INST_NUM-1:0];
    wire [1:0]  pipe_tile_act_tid [SUB_INST_NUM-1:0]; 
    
    wire        pipe_tile_w_sel   [SUB_INST_NUM-1:0];
    wire [1:0]  pipe_tile_w_tid   [SUB_INST_NUM-1:0];
    wire [3:0]  pipe_tile_mode    [SUB_INST_NUM-1:0];
    wire        pipe_tile_relu    [SUB_INST_NUM-1:0];
    wire        pipe_tile_clr_acc [SUB_INST_NUM-1:0];
    wire        pipe_tile_clr_out [SUB_INST_NUM-1:0];
    wire [15:0] pipe_tile_scale   [SUB_INST_NUM-1:0];
    wire [7:0]  pipe_tile_zp      [SUB_INST_NUM-1:0];

    // Tile WB Fields
    wire [9:0]  pipe_wb_addr    [SUB_INST_NUM-1:0];
    wire [7:0]  pipe_wb_reorder [SUB_INST_NUM-1:0];
    wire [7:0]  pipe_wb_dabus   [SUB_INST_NUM-1:0];
    wire [3:0]  pipe_wb_mask    [SUB_INST_NUM-1:0];

    // Barrier Fields
    wire [4:0]  pipe_sync_req   [SUB_INST_NUM-1:0];
    wire [1:0]  pipe_agu_wait   [SUB_INST_NUM-1:0];
    wire        pipe_tile_wait  [SUB_INST_NUM-1:0];
    wire [5:0]  pipe_status     [SUB_INST_NUM-1:0];

    // Intermediate wires for RFBPCtrl Stall
    wire [SUB_INST_NUM-1:0] rfbpctrl_stall_bus;
    wire [SUB_INST_NUM-1:0] tile_wb_is_set [3:0]; // Array of vectors

    // ====================================================================
    // Logic Implementation
    // ====================================================================

    // Output assignment for Fetch Enable
    // fdu_fifo_rd_en comes from SkidBuffer logic.
    assign o_fetch = fdu_fifo_rd_en; 

    // Core Busy Bus aggregation
    // Currently relying on Barrier output logic to drive this
    wire [SUB_INST_NUM-1:0] core_busy_internal_bus;
    assign o_core_busy_bus = core_busy_internal_bus;

    // Output Assignment for Instruction Error
    assign o_error_op = pipe_error_op;

    genvar i;
    generate
        for(i = 0; i < SUB_INST_NUM; i = i + 1) begin : gen_slice_logic

            // ----------------------------------------------------------------
            // 1. Fetch & Decode Unit (The Front-End)
            // ----------------------------------------------------------------
            FetchDecodeUnit #(
                .DWIDTH(32)
            ) u_FetchDecodeUnit (
                .clk            (clk),
                .rst_n          (rst_n),

                // FIFO Interface
                .i_fifo_data    (i_inst[ (i+1)*32-1 : i*32 ]),
                // Assume FIFO is available (aggressive fetch), valid checked by i_fifo_valid
                .i_fifo_empty   (i_inst_empty[i]), 
                .i_fifo_valid   (i_inst_valid[i]),
                .o_fifo_rd_en   (fdu_fifo_rd_en[i]),

                // Stall Control (Feedback from Barrier)
                // If Barrier says "fetch" (go), then stall is 0. If "fetch" is 0, stall is 1.
                .i_backend_stall(~barrier_fetch_enable[i]),

                // Decoded Outputs (To Pipeline Registers)
                
                .o_regfile_tile_wb_op (pipe_regfile_tile_wb_op[i]),
                .o_regfile_core_in_op (pipe_regfile_core_in_op[i]),
                .o_regfile_read_op    (pipe_regfile_read_op[i]),
                .o_block_sync_op      (pipe_block_sync_op[i]),
                .o_tile_mode_op       (pipe_tile_mode_op[i]),
                .o_tile_en_op         (pipe_tile_en_op[i]),
                .o_tile_wb_op         (pipe_tile_wb_op[i]),
                .o_core_out_op        (pipe_core_out_op[i]),
                .o_error_op           (pipe_error_op[i]),

                .o_opcode             (pipe_opcode[i]),
                
                .o_rf_src_sel         (pipe_rf_src_sel[i]),
                .o_addr               (pipe_addr[i]),
                .o_len                (pipe_len[i]),
                .o_agu_mode           (pipe_agu_mode[i]),
                .o_thread_id          (pipe_thread_id[i]),

                .o_core_out_sel       (pipe_core_out_sel[i]),
                .o_core_out_val       (pipe_core_out_valid[i]),
                .o_core_out_tid       (pipe_core_out_tid[i]),

                .o_tile_act_sel       (pipe_tile_act_sel[i]),
                .o_tile_act_tid       (pipe_tile_act_tid[i]),
                .o_tile_w_sel         (pipe_tile_w_sel[i]),
                .o_tile_w_tid         (pipe_tile_w_tid[i]),
                .o_tile_mode          (pipe_tile_mode[i]),
                .o_tile_relu          (pipe_tile_relu[i]),
                .o_tile_clr_acc       (pipe_tile_clr_acc[i]),
                .o_tile_clr_out       (pipe_tile_clr_out[i]),
                .o_tile_scale         (pipe_tile_scale[i]),
                .o_tile_zp            (pipe_tile_zp[i]),

                .o_wb_addr            (pipe_wb_addr[i]),
                .o_wb_reorder         (pipe_wb_reorder[i]),
                .o_wb_dabus           (pipe_wb_dabus[i]),
                .o_wb_mask            (pipe_wb_mask[i]),


                .o_sync_req           (pipe_sync_req[i]),
                .o_agu_wait           (pipe_agu_wait[i]),
                .o_tile_wait          (pipe_tile_wait[i]),
                .o_status             (pipe_status[i])
            );

            // ----------------------------------------------------------------
            // 2. Tile State Logic
            // ----------------------------------------------------------------
            TileState TileState_inst(
                .clk                    (clk),
                .rst_n                  (rst_n),

                .i_tile_en_op           (pipe_tile_en_op[i]),
                .i_tile_mode_op         (pipe_tile_mode_op[i]),

                .i_tile_clear_acc       (pipe_tile_clr_acc[i]),
                .i_tile_clear_out       (pipe_tile_clr_out[i]),
                .i_tile_relu            (pipe_tile_relu[i]),
                .i_tile_mode            (pipe_tile_mode[i]),
                
                .i_tile_act_select      (pipe_tile_act_sel[i]), // 1-bit
                .i_tile_weight_select   (pipe_tile_w_sel[i]), // 1-bit

                .i_tile_act_thread_id   (pipe_tile_act_tid[i]),
                .i_tile_weight_thread_id(pipe_tile_w_tid[i]),

                .i_tile_scale           (pipe_tile_scale[i]),
                .i_tile_zero_point      (pipe_tile_zp[i]),

                .o_tile_enable          (o_tile_enable[i]),
                .o_tile_mode            (o_tile_mode[i]),
                .o_tile_relu            (o_tile_relu[i]),
                .o_tile_clear_acc       (o_tile_clear_acc[i]),
                .o_tile_clear_out       (o_tile_clear_out[i]),

                .o_tile_act_thread_id   (o_tile_act_thread_id[i]),
                .o_tile_weight_thread_id(o_tile_weight_thread_id[i]),

                .o_tile_act_select      (o_tile_act_select[i]),
                .o_tile_weight_select   (o_tile_weight_select[i]),
                
                .o_tile_scale           (o_tile_scale[i]),
                .o_tile_zero_point      (o_tile_zero_point[i])
            );

            // ----------------------------------------------------------------
            // 3. Tile Write Back Logic
            // ----------------------------------------------------------------
            TileWB TileWB_inst(
                .clk                    (clk),
                .rst_n                  (rst_n),

                .i_tile_wb_op           (pipe_tile_wb_op[i]),
                // Combine vector for is_set check (Checking if any bank is set)
                .i_tile_wb_is_set       ({tile_wb_is_set[0][i], tile_wb_is_set[1][i], tile_wb_is_set[2][i], tile_wb_is_set[3][i]}), 

                .i_tile_dabus           (pipe_wb_dabus[i]),
                .i_tile_wb_reorder      (pipe_wb_reorder[i]),
                .i_tile_wb_address      (pipe_wb_addr[i]),
                .i_tile_wb_mask         (pipe_wb_mask[i]),

                .o_tile_dabus           (o_tile_dabus[i]),
                .o_tile_dabus_valid     (o_tile_dabus_valid[i]),    

                .o_tile_wb_reorder      (o_tile_reorder[i]),
                .o_tile_wb_reorder_valid(o_tile_reorder_valid[i]),

                .o_tile_wb_address      (o_tile_wb_address[i]),
                .o_tile_wb_address_valid(o_tile_wb_address_valid[i]),
                .o_tile_wb_mask         (o_tile_wb_mask[i]),

                .o_tilewb_fifo_full     (o_tilewb_fifo_full[i]),
                .o_error_tile_wb_conflict(o_error_tile_wb_conflict[i])
            );

            // ----------------------------------------------------------------
            // 4. Register File Bank Port Control (Issue Logic)
            // ----------------------------------------------------------------
            RFBPCtrl RFBPCtrl_inst(
                .clk                        (clk),
                .rst_n                      (rst_n),

                .i_agu_slot_ready           (i_agu_slot_ready_bus[i]),
                .i_agu_ready                (i_agu_ready_bus[i]),

                .i_regfile_tile_wb_op       (pipe_regfile_tile_wb_op[i]),
                .i_regfile_core_in_op       (pipe_regfile_core_in_op[i]),
                .i_regfile_read_op          (pipe_regfile_read_op[i]),

                .i_regfile_addr             (pipe_addr[i]),
                .i_regfile_len              (pipe_len[i]),
                .i_regfile_sel              (pipe_rf_src_sel[i]), // Takes 12-bit
                .i_agu_mode                 (pipe_agu_mode[i]),
                .i_thread_id                (pipe_thread_id[i]),

                .o_agu_addr                 (o_agu_addr[i]),
                .o_agu_len                  (o_agu_len[i]),
                .o_agu_start                (o_agu_start[i]),
                .o_agu_mode                 (o_agu_mode[i]),
                .o_thread_id                (o_agu_thread_id[i]),
                .o_agu_read                 (o_agu_read[i]),
                .o_agu_write                (o_agu_write[i]),

                .o_rfbp_sel                 (o_rfbp_sel[i]),
                .o_wen                      (o_rfbp_wen[i]),

                .o_tile_wb_is_set           (tile_wb_is_set[i]),

                .o_stall                    (rfbpctrl_stall_bus[i])
            );

            // ----------------------------------------------------------------
            // 5. Core Output Control
            // ----------------------------------------------------------------
            CoreOutputCtrl CoreOutputCtrl_inst(
                .clk                             (clk),
                .rst_n                           (rst_n),

                .i_core_out_op                   (pipe_core_out_op[i]),
                .i_thread_id                     (pipe_core_out_tid[i]),
                .i_core_output_select            (pipe_core_out_sel[i]),
                .i_core_output_select_valid      (pipe_core_out_valid[i]),

                .o_core_output_thread_id         (o_core_output_thread_id[i]),
                .o_core_output_select            (o_core_output_select[i]),
                .o_core_output_select_valid      (o_core_output_select_valid[i])
            );

            // ----------------------------------------------------------------
            // 6. Barrier / Global Sync (Hazard Control)
            // ----------------------------------------------------------------
            Barrier #(
                .SLOT_ID (i)
            ) Barrier_inst (
                .i_block_sync_op                (pipe_block_sync_op[i]),

                .i_sync_req                     (pipe_sync_req[i]), 
                .i_wait_agu_slot                (pipe_agu_wait[i]),
                .i_wait_tile                    (pipe_tile_wait[i]), // 1-bit
                .i_status                       (pipe_status[i]),

                .i_agu_slot_ready               (i_agu_slot_ready_bus[i]),
                .i_tile_busy                    (i_tile_busy_bus[i]),

                .i_core_busy                    (core_busy_internal_bus), // Feedback from all Barriers
                .i_ext_busy                     (i_ext_busy),

                .i_rfbpctrl_stall               (rfbpctrl_stall_bus[i]),

                .o_status                       (o_status_bus[i]),
                .o_busy                         (core_busy_internal_bus[i]), // Output to bus
                .o_fetch                        (barrier_fetch_enable[i]) // Output to stall FDU
            );

        end
    endgenerate

endmodule