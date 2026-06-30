// Versiob B0
module CoreOutputCtrl(

    clk,
    rst_n,

    i_core_out_op,

    i_thread_id,
    i_core_output_select,
    i_core_output_select_valid,

    o_core_output_thread_id,
    o_core_output_select,
    o_core_output_select_valid

);
    localparam CORE_SELECT_WIDTH = 2;
    localparam THREAD_ID_WIDTH = 2;

    input clk;
    input rst_n;

    input  i_core_out_op;

    input [THREAD_ID_WIDTH-1 : 0] i_thread_id;
    input [CORE_SELECT_WIDTH-1 : 0] i_core_output_select;
    input i_core_output_select_valid;

    output [THREAD_ID_WIDTH-1 : 0] o_core_output_thread_id;
    output [CORE_SELECT_WIDTH-1 : 0] o_core_output_select;
    output o_core_output_select_valid;
    
    reg [CORE_SELECT_WIDTH-1 : 0] core_output_select_reg;
    reg core_output_select_valid_reg;
    reg [THREAD_ID_WIDTH-1 : 0] core_output_thread_id;

    assign o_core_output_select = core_output_select_reg;
    assign o_core_output_select_valid = core_output_select_valid_reg;
    assign o_core_output_thread_id = core_output_thread_id;

    always @(posedge clk) begin
        if(!rst_n) begin
            core_output_select_reg <= 0;
            core_output_select_valid_reg <= 0;
            core_output_thread_id <= 0;
        end
        else begin
            
            core_output_select_reg <= (i_core_out_op)? i_core_output_select: core_output_select_reg;
            core_output_select_valid_reg <= (i_core_out_op)? i_core_output_select_valid : core_output_select_valid_reg;
            core_output_thread_id <= (i_core_out_op)? i_thread_id : core_output_thread_id;
        end
    end
    
endmodule