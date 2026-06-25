module PEv5 #(
    parameter PE_ROW_ID = 0,
    parameter PE_COL_ID = 0,
    parameter PRE_LOAD_WIDTH = 8,
    parameter COMPUTE_WIDTH = 16,
    parameter PACK_WIDTH = 32,
    parameter O_DATA_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,

    // Control Signals
    input wire i_pe_enable,
    input wire [3:0] i_mode, // [1:0] Compute Mode, [3:2] Sparse Mode
    input wire i_clear_acc,
    input wire i_clear_out,
    
    // Indexing
    input wire [1:0] i_dense_index,
    input wire [1:0] i_sparse_index,

    // Data Inputs
    input wire [PRE_LOAD_WIDTH-1:0] i_act_simd,
    input wire [PRE_LOAD_WIDTH-1:0] i_weight_simd,
    input wire [PACK_WIDTH-1:0]     i_systolic_acts,
    input wire [PRE_LOAD_WIDTH-1:0] i_systolic_weight,
    input wire [15:0]               i_scale, 

    // Outputs
    output wire [O_DATA_WIDTH-1:0] o_acc,
    output reg  [O_DATA_WIDTH-1:0] o_scale_acc_up,
    output reg  [O_DATA_WIDTH-1:0] o_scale_acc_down,
    output reg                     o_scale_acc_valid
);

    // ====================================================================
    // Parameters & Constants
    // ====================================================================
    localparam ACC_WIDTH = 32;
    localparam DSP_RESULT_WIDTH = 32;
    
    localparam COMPUTE_MODE_WIDTH = 2;
    localparam SYSTOLIC_MODE = 2'b00;
    localparam SIMD_MODE     = 2'b01;
    localparam SCALE_MODE    = 2'b10;

    // ====================================================================
    // Internal Signals
    // ====================================================================
    
    // Pipeline Registers
    reg pe_enable_stage_1, pe_enable_stage_2;
    reg [COMPUTE_MODE_WIDTH-1:0] compute_mode_stage_1, compute_mode_stage_2;
    reg [1:0] dense_index_stage_1, dense_index_stage_2, dense_index_stage_3;
    reg clear_acc_stage_1, clear_acc_stage_2;
    reg scale_valid_stage_3;

    // Data Path Signals
    wire [COMPUTE_MODE_WIDTH-1:0] current_compute_mode;
    wire [1:0] current_sparse_mode;

    // DSP Inputs & Logic
    reg signed [COMPUTE_WIDTH-1:0] dsp_in_a; // Registered input to DSP
    reg signed [COMPUTE_WIDTH-1:0] next_dsp_in_a; // Combinational logic for A
    
    reg signed [COMPUTE_WIDTH-1:0] dsp_in_b; // Registered input to DSP
    reg signed [COMPUTE_WIDTH-1:0] next_dsp_in_b; // Combinational logic for B
    
    reg signed [DSP_RESULT_WIDTH-1:0] m_reg;
    reg signed [ACC_WIDTH-1:0]        p_reg;

    // Helper Signals
    wire signed [PRE_LOAD_WIDTH-1:0] systolic_act_selected;
    wire [1:0] act_index_select;
    wire signed [15:0] p_reg_feedback_slice; 

    // ====================================================================
    // Control Logic & Pipelining
    // ====================================================================
    assign current_compute_mode = i_mode[COMPUTE_MODE_WIDTH-1:0];
    assign current_sparse_mode  = i_mode[3:2];

    always @(posedge clk) begin
        if (!rst_n) begin
            pe_enable_stage_1    <= 0;
            pe_enable_stage_2    <= 0;
            compute_mode_stage_1 <= 0;
            compute_mode_stage_2 <= 0;
            dense_index_stage_1  <= 0;
            dense_index_stage_2  <= 0;
            clear_acc_stage_1    <= 0;
            clear_acc_stage_2    <= 0;            
        end else begin
            pe_enable_stage_1    <= i_pe_enable;
            pe_enable_stage_2    <= pe_enable_stage_1;
            
            compute_mode_stage_1 <= current_compute_mode;
            compute_mode_stage_2 <= compute_mode_stage_1;
            
            dense_index_stage_1  <= i_dense_index;
            dense_index_stage_2  <= dense_index_stage_1;
            
            clear_acc_stage_1    <= i_clear_acc;
            clear_acc_stage_2    <= clear_acc_stage_1;
        end
    end

    // ====================================================================
    // Stage 0: Input Selection Logic (Combinational)
    // ====================================================================
    
    // 1. Data Selection Logic
    assign act_index_select = (current_sparse_mode == 2'b11) ? i_dense_index : i_sparse_index;
    assign systolic_act_selected = i_systolic_acts[(act_index_select * PRE_LOAD_WIDTH) +: PRE_LOAD_WIDTH];

    // 2. Feedback Slicing (Slices from Accumulator)
    assign p_reg_feedback_slice = (i_dense_index == 2'b00) ? p_reg[15:0] : 
                                  (i_dense_index == 2'b01) ? (p_reg[31:16] + {{15{1'b0}}, p_reg[15]}) : 16'd0;

    // 3. DSP Input Muxing (With Signed Compensation)
    always @(*) begin
        // Default assignments
        next_dsp_in_a = {COMPUTE_WIDTH{1'b0}};
        next_dsp_in_b = {COMPUTE_WIDTH{1'b0}};

        case (current_compute_mode)
            SCALE_MODE: begin
                // Input B: Scale Factor (Common)
                next_dsp_in_b = {1'b0, i_scale[14:0]};
                next_dsp_in_a = p_reg_feedback_slice;
                
            end
            
            SIMD_MODE: begin
                next_dsp_in_a = {{8{i_act_simd[7]}}, i_act_simd};
                next_dsp_in_b = {{8{i_weight_simd[7]}}, i_weight_simd};
            end
            
            default: begin // SYSTOLIC_MODE
                next_dsp_in_a = {{8{systolic_act_selected[7]}}, systolic_act_selected};
                next_dsp_in_b = {{8{i_systolic_weight[7]}}, i_systolic_weight};
            end
        endcase
    end

    // 4. DSP Input Register Latching
    always @(posedge clk) begin
        if (!rst_n) begin
            dsp_in_a <= 0;
            dsp_in_b <= 0;
        end else if (i_pe_enable) begin
            dsp_in_a <= next_dsp_in_a;
            dsp_in_b <= next_dsp_in_b;
        end
    end

    // ====================================================================
    // Stage 1: DSP Multiplier (M-Register)
    // ====================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            m_reg <= 0;
        end else begin
            m_reg <= dsp_in_a * dsp_in_b;
        end
    end

    // ====================================================================
    // Stage 2: DSP Accumulator (P-Register)
    // ====================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            p_reg <= 0;
        end else begin
            if (clear_acc_stage_2) begin
                p_reg <= 0;
            end else if (pe_enable_stage_2) begin
                if (compute_mode_stage_2 == SCALE_MODE) begin
                    // Note: Overwriting p_reg with m_reg effectively replaces the Accumulator 
                    // with the scaled part. Ensure Sequence is reload -> Scale High -> Reload -> Scale Low
                    // or similar, as p_reg is destroyed here.
                    p_reg <= m_reg; 
                end else begin
                    p_reg <= p_reg + m_reg; // MAC
                end
            end
        end
    end

    assign o_acc = p_reg;

    // ====================================================================
    // Output Logic
    // ====================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            dense_index_stage_3 <= 0;
            scale_valid_stage_3 <= 0;
        end else begin
            dense_index_stage_3 <= dense_index_stage_2;
            
            if (clear_acc_stage_2) begin
                scale_valid_stage_3 <= 0;
            end else if (pe_enable_stage_2 && compute_mode_stage_2 == SCALE_MODE) begin
                scale_valid_stage_3 <= 1;
            end else begin
                scale_valid_stage_3 <= 0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n || i_clear_out) begin
            o_scale_acc_up    <= 0;
            o_scale_acc_down  <= 0;
            o_scale_acc_valid <= 0;
        end else begin
            if (scale_valid_stage_3) begin
                if (dense_index_stage_3 == 2'b01) begin 
                    o_scale_acc_up    <= p_reg;
                    o_scale_acc_valid <= 1; 
                end 
                else if (dense_index_stage_3 == 2'b00) begin
                    o_scale_acc_down  <= p_reg;
                end
            end
        end
    end

endmodule