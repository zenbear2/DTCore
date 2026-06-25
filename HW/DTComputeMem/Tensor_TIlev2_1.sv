module Tensor_Tilev2_1 #(
    parameter TILE_ID = 0,

    parameter I_DATA_WIDTH = 32,
    parameter O_DATA_WIDTH = 8,

    parameter COMPUTE_WIDTH = 16,

    parameter ARRAY_HEIGHT = 4,
    parameter ARRAY_WIDTH = 4

)(
    clk,
    rst_n,

    i_act_tile,
    i_act_tile_valid,
    i_data_act_thread_id,

    i_weight_tile,
    i_weight_tile_valid,
    i_data_weight_thread_id,

    i_scale,
    i_zero_point,

    i_relu_valid,

    i_bus_select,
    i_bus_select_valid,

    i_reorder_select,
    i_reorder_select_valid,

    i_tile_enable,

    i_tile_act_thread_id,
    i_tile_weight_thread_id,

    i_mode,
    i_clear_pe_acc, // Clear PE Accumulator
    i_clear_pe_out, // Clear PE Output

    o_tile,
    o_tile_busy,
    o_tile_valid
);

localparam ELEMENT_WIDTH = 8;
localparam INDEX_WIDTH = 2;
localparam SCALE_WIDTH = 16;
localparam ZERO_POINT_WIDTH = 8;
localparam RELU_WIDTH = 8;
localparam SELECT_WIDTH = $clog2(ARRAY_WIDTH);
localparam COMPUTE_MODE_WIDTH = 2;
localparam SPARSE_MODE_WIDTH = 2;
localparam PE_MODE_WIDTH = COMPUTE_MODE_WIDTH + SPARSE_MODE_WIDTH;

localparam PE_O_DATA_WIDTH = COMPUTE_WIDTH*2;
localparam BUS_O_DATA_WIDTH = PE_O_DATA_WIDTH;

localparam THREAD_ID_WIDTH = 2;

input clk;
input rst_n;

input [I_DATA_WIDTH*ARRAY_WIDTH-1:0] i_act_tile;
input i_act_tile_valid;
input [THREAD_ID_WIDTH-1:0] i_data_act_thread_id;

input [I_DATA_WIDTH*ARRAY_HEIGHT-1:0] i_weight_tile;
input i_weight_tile_valid;
input [THREAD_ID_WIDTH-1:0] i_data_weight_thread_id;

input [SCALE_WIDTH-1:0] i_scale;
input [ZERO_POINT_WIDTH-1:0] i_zero_point;

input [ARRAY_WIDTH-1:0] i_relu_valid;

input [SELECT_WIDTH*ARRAY_WIDTH-1:0] i_bus_select;
input [ARRAY_WIDTH-1:0] i_bus_select_valid;

input i_tile_enable;

input [THREAD_ID_WIDTH-1:0] i_tile_act_thread_id;
input [THREAD_ID_WIDTH-1:0] i_tile_weight_thread_id;

input [PE_MODE_WIDTH-1:0] i_mode;
input i_clear_pe_acc;
input i_clear_pe_out;

input [SELECT_WIDTH*ARRAY_WIDTH-1:0] i_reorder_select;
input [ARRAY_WIDTH-1:0]i_reorder_select_valid;

output [O_DATA_WIDTH*ARRAY_WIDTH-1:0] o_tile;
output                   o_tile_busy;
output [ARRAY_WIDTH-1:0] o_tile_valid;

wire [INDEX_WIDTH-1:0] dense_index;

wire act_put_data_pe_array;
wire weight_put_data_pe_array;

wire pe_enable;


wire [BUS_O_DATA_WIDTH*ARRAY_WIDTH-1:0] pe_array_data;
wire [ARRAY_WIDTH-1:0] pe_array_data_valid;
wire pe_array_all_valid = &pe_array_data_valid;

index_counter u_index_counter (
    .clk(clk),
    .rst_n(rst_n),

    .i_tile_enable(i_tile_enable),
    .i_mode(i_mode),

    .i_act_tile_valid(i_act_tile_valid),
    .i_weight_tile_valid(i_weight_tile_valid),

    .i_tile_act_thread_id(i_tile_act_thread_id),
    .i_tile_weight_thread_id(i_tile_weight_thread_id),

    .i_data_act_thread_id(i_data_act_thread_id),
    .i_data_weight_thread_id(i_data_weight_thread_id),

    .o_index_counter(dense_index),
    .o_act_put_data(act_put_data_pe_array),
    .o_weight_put_data(weight_put_data_pe_array),
    .o_pe_enable(pe_enable),

    .o_tile_busy(o_tile_busy)
);


DynaPE_Arrayv2_1 #(
    .ARRAY_ID(TILE_ID),
    .INDEX_WIDTH(2),
    .ELEMENT_WIDTH(8),
    .COMPUTE_WIDTH(16),
    .I_PACK_WIDTH(32),

    .ARRAY_HEIGHT(ARRAY_HEIGHT),
    .ARRAY_WIDTH(ARRAY_WIDTH)
) u_dyna_pe_array (
    .clk(clk),
    .rst_n(rst_n),

    .i_act_pe_array(i_act_tile),
    .i_act_put_data_pe_array(act_put_data_pe_array),

    .i_weight_pe_array(i_weight_tile),
    .i_weight_put_data_pe_array(weight_put_data_pe_array),

    .i_dense_index(dense_index),
    .i_shift(pe_enable),

    .i_scale(i_scale),

    .i_bus_select(i_bus_select),
    .i_bus_select_valid(i_bus_select_valid),

    .i_pe_enable(pe_enable),

    .i_mode(i_mode),
    .i_clear_pe_acc(i_clear_pe_acc), // Clear PE
    .i_clear_pe_out(i_clear_pe_out), // Clear PE

    .o_data_bus(pe_array_data),
    .o_data_bus_valid(pe_array_data_valid)
);

genvar i;
generate
    for (i = 0; i < ARRAY_WIDTH; i = i + 1) begin : REORDER_BUS

        Quantize_Reorder_Buffer #(
        //Quantize_Reorder_Buffer #(
        
            .I_DATA_WIDTH(BUS_O_DATA_WIDTH),
            .O_DATA_WIDTH(O_DATA_WIDTH),
            .NUM_IN_PORTS(ARRAY_WIDTH),
            //.ZERO_POINT_WIDTH(ZERO_POINT_WIDTH),
            .IS_UINT8(0)
        ) u_quantize_reorder_buffer (
            .clk(clk),
            .rst_n(rst_n),

            .i_data(pe_array_data),
            .i_data_valid(pe_array_all_valid),

            //.i_zero_point(i_zero_point),

            .i_relu_valid(i_relu_valid[i]),

            .i_select(i_reorder_select[(i+1)*SELECT_WIDTH-1:i*SELECT_WIDTH]),
            .i_select_valid(i_reorder_select_valid[i]),

            .o_data(o_tile[(i+1)*O_DATA_WIDTH-1:i*O_DATA_WIDTH]),
            .o_data_valid(o_tile_valid[i])
        );


    end

endgenerate

endmodule