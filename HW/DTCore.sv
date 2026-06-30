// Version B0
module DTCore #(
    parameter CORE_ID = 0
)(
    clk,
    rst_n,
    
    i_inst,
    i_inst_valid,

    i_core_data,
    i_core_data_thread_id,

    o_core_data,
    o_core_data_thread_id,
    
    o_core_data_last,
    o_core_data_valid,

    o_tilewb_fifo_full,
    o_error_tile_wb_conflict,
    o_error_op,

    o_agu_ready,
    o_agu_busy,
    o_agu_slot_ready,
    o_agu_slot_busy,

    i_ext_busy,
    o_core_busy_bus,
    o_tile_busy_bus,
    o_status_bus,

    o_read_data,

    o_fetch     

);

localparam RFBP_NUM = 4;
localparam BRAM_INST = 8;
localparam TILE_INST = 4;
localparam CORE_DATA_WIDTH = 128;
localparam CORE_INPUT_INST = 4;
localparam CORE_OUTPUT_INST = 4;
localparam CORE_SELECT_WIDTH = 2;

localparam TILE_ACT_SELECT_WIDTH = 1;
localparam TILE_WEIGHT_SELECT_WIDTH = 1;
localparam THREAD_ID_WIDTH = 2;
localparam DABUS_WIDTH = 8;
localparam REORDER_WIDTH = 8;
localparam ADDR_WIDTH = 10;
localparam MASK_WIDTH = 4;
localparam LEN_WIDTH = 10;
localparam AGU_MODE_WIDTH = 2;
localparam REGFILE_SRC_WIDTH = 3;

localparam PE_MODE_WIDTH = 4;
localparam INV_SCALE_WIDTH = 16;
localparam ZERO_POINT_WIDTH = 8;

localparam INST_WIDTH = 128;


input clk;
input rst_n;
input [INST_WIDTH-1 : 0] i_inst;
input [TILE_INST-1 : 0] i_inst_valid;

input [CORE_DATA_WIDTH-1 : 0] i_core_data [CORE_INPUT_INST-1:0];
input [THREAD_ID_WIDTH-1 : 0] i_core_data_thread_id [CORE_INPUT_INST-1:0];

output [CORE_DATA_WIDTH-1 : 0] o_core_data [CORE_OUTPUT_INST-1:0];
output [THREAD_ID_WIDTH-1 : 0] o_core_data_thread_id [CORE_OUTPUT_INST-1:0];

output [CORE_OUTPUT_INST-1 : 0] o_core_data_last;
output [CORE_OUTPUT_INST-1 : 0] o_core_data_valid;

// TileWB FIFO
output [TILE_INST-1 : 0] o_tilewb_fifo_full;
output [TILE_INST-1 : 0] o_error_tile_wb_conflict;
output [TILE_INST-1 : 0] o_error_op;

// Address Generator Uint
output [RFBP_NUM-1 : 0] o_agu_ready;
output [RFBP_NUM-1 : 0] o_agu_busy;
output [1 : 0] o_agu_slot_ready [RFBP_NUM-1 : 0];
output [1 : 0] o_agu_slot_busy [RFBP_NUM-1 : 0];

// busy signal
input i_ext_busy;
output [TILE_INST-1 : 0] o_core_busy_bus;
output [TILE_INST-1 : 0] o_tile_busy_bus;
output [5 : 0] o_status_bus [TILE_INST-1 : 0];

// Core Read Data From FIFO
output [3:0] o_read_data;

// Fetch signal
output [TILE_INST-1 : 0] o_fetch;


//Tile State
wire [TILE_INST-1 : 0] tile_enable;
wire [PE_MODE_WIDTH-1:0] tile_mode [0:TILE_INST-1];
wire [TILE_INST-1 : 0] tile_relu;
wire [TILE_INST-1 : 0] tile_clear_acc;
wire [TILE_INST-1 : 0] tile_clear_out;

wire [TILE_ACT_SELECT_WIDTH-1 : 0] tile_act_select [TILE_INST-1 : 0];
wire [TILE_WEIGHT_SELECT_WIDTH-1 : 0] tile_weight_select [TILE_INST-1 : 0];

wire [THREAD_ID_WIDTH-1 : 0] tile_act_thread_id [TILE_INST-1 : 0];
wire [THREAD_ID_WIDTH-1 : 0] tile_weight_thread_id [TILE_INST-1 : 0];

wire [INV_SCALE_WIDTH-1 : 0] tile_scale [TILE_INST-1 : 0];
wire [ZERO_POINT_WIDTH-1 : 0] tile_zero_point [TILE_INST-1 : 0];

// Tile WB
wire [DABUS_WIDTH-1 : 0] tile_dabus [TILE_INST-1 : 0];
wire [TILE_INST-1 : 0] tile_dabus_valid;

wire [REORDER_WIDTH-1 : 0] tile_reorder [TILE_INST-1 : 0];
wire [TILE_INST-1 : 0] tile_reorder_valid;

wire [ADDR_WIDTH-1 : 0] tile_wb_address [TILE_INST-1 : 0];
wire [TILE_INST-1 : 0] tile_wb_address_valid;
wire [MASK_WIDTH-1 : 0] tile_wb_mask [TILE_INST-1 : 0];


// RFBPCtrl Outputs
wire [ADDR_WIDTH-1 : 0] agu_addr [RFBP_NUM-1 : 0];
wire [LEN_WIDTH-1 : 0] agu_len [RFBP_NUM-1 : 0];
wire [RFBP_NUM-1 : 0] agu_start;

wire [AGU_MODE_WIDTH-1 : 0] agu_mode [RFBP_NUM-1 : 0];
wire [THREAD_ID_WIDTH-1 : 0] agu_thread_id [RFBP_NUM-1 : 0];
wire [RFBP_NUM-1 : 0] agu_read;
wire [RFBP_NUM-1 : 0] agu_write;

wire [REGFILE_SRC_WIDTH*4-1 : 0] rfbp_sel [RFBP_NUM-1 : 0];
wire [RFBP_NUM-1 : 0] rfbp_wen;

// Core Output Ctrl Outputs
wire [THREAD_ID_WIDTH-1 : 0] core_output_thread_id_ctrl [CORE_OUTPUT_INST-1 : 0];
wire [THREAD_ID_WIDTH-1 : 0] core_output_thread_id_cm [CORE_OUTPUT_INST-1 : 0];

wire [CORE_SELECT_WIDTH-1 : 0] core_output_select [CORE_OUTPUT_INST-1 : 0];
wire [CORE_OUTPUT_INST-1 : 0]core_output_select_valid;


genvar i;
generate
    for(i = 0 ; i <= CORE_OUTPUT_INST-1 ; i=i+1)begin :gen_core_output_valid
        assign o_core_data_valid[i] = (core_output_thread_id_cm[i] == core_output_thread_id_ctrl[i]) & core_output_select_valid[i];
        assign o_core_data_thread_id[i] = core_output_thread_id_cm[i];
    end
endgenerate


DTControllerv3 u_DTController(
    .clk(clk),
    .rst_n(rst_n),

    .i_inst(i_inst),
    .i_inst_valid(i_inst_valid),

    .i_ext_busy(i_ext_busy),
    .i_agu_slot_ready_bus(o_agu_slot_ready),
    .i_agu_ready_bus(o_agu_ready),
    .i_tile_busy_bus(o_tile_busy_bus),

    .o_tile_enable(tile_enable),
    .o_tile_mode(tile_mode),
    .o_tile_relu(tile_relu),
    .o_tile_clear_acc(tile_clear_acc),
    .o_tile_clear_out(tile_clear_out),

    .o_tile_act_select(tile_act_select),
    .o_tile_weight_select(tile_weight_select),

    .o_tile_act_thread_id(tile_act_thread_id),
    .o_tile_weight_thread_id(tile_weight_thread_id),

    .o_tile_scale(tile_scale),
    .o_tile_zero_point(tile_zero_point),

    .o_tile_dabus(tile_dabus),
    .o_tile_dabus_valid(tile_dabus_valid),

    .o_tile_reorder(tile_reorder),
    .o_tile_reorder_valid(tile_reorder_valid),

    .o_tile_wb_address(tile_wb_address),
    .o_tile_wb_address_valid(tile_wb_address_valid),
    .o_tile_wb_mask(tile_wb_mask),


    .o_tilewb_fifo_full(o_tilewb_fifo_full),             // STOP fetch instruction until finish last operation
    .o_error_tile_wb_conflict(o_error_tile_wb_conflict), // Error Tile want write back bus regfile port not ready
    .o_error_op(o_error_op),
    
    .o_agu_addr(agu_addr),
    .o_agu_len(agu_len),
    .o_agu_start(agu_start),
    .o_agu_mode(agu_mode),
    .o_agu_thread_id(agu_thread_id),
    .o_agu_read(agu_read),
    .o_agu_write(agu_write),

    .o_rfbp_sel(rfbp_sel),
    .o_rfbp_wen(rfbp_wen),
    
    .o_core_output_thread_id(core_output_thread_id_ctrl),
    .o_core_output_select(core_output_select),
    .o_core_output_select_valid(core_output_select_valid),

    .o_core_busy_bus(o_core_busy_bus),
    .o_status_bus(o_status_bus),
    .o_fetch(o_fetch)
);

DTComputeMemv2_4 #(
    .CORE_ID(CORE_ID),
    .TILE_INST(TILE_INST),
    .BRAM_INST(BRAM_INST),
    .SCALE_WIDTH(INV_SCALE_WIDTH),
    .ZERO_POINT_WIDTH(ZERO_POINT_WIDTH),
    .RELU_WIDTH(8),
    .SUB_RAM_ADDR_WIDTH(10)
) u_DTComputeMemv2(
    .clk(clk),
    .rst_n(rst_n),

    .i_core_data(i_core_data),
    .i_core_data_thread_id(i_core_data_thread_id),

    .o_core_data(o_core_data),
    .o_core_data_thread_id(core_output_thread_id_cm),

    .o_core_data_last(o_core_data_last),

    .i_tile_act_select(tile_act_select),
    .i_tile_weight_select(tile_weight_select),

    .i_rfbp_sel(rfbp_sel),

    .i_agu_start(agu_start),
    .i_agu_address(agu_addr),
    .i_agu_length(agu_len),
    .i_agu_mode(agu_mode),
    .i_agu_thread_id(agu_thread_id),
    .i_agu_read(agu_read),
    .i_agu_write(agu_write),

    .o_agu_ready(o_agu_ready),
    .o_agu_busy(o_agu_busy),

    .o_agu_slot_ready(o_agu_slot_ready),
    .o_agu_slot_busy(o_agu_slot_busy),

    .i_wb_addr(tile_wb_address),
    .i_wb_valid(tile_wb_address_valid),
    .i_wb_mask(tile_wb_mask),


    .i_tile_bus_mux(tile_dabus),
    .i_tile_bus_mux_valid(tile_dabus_valid),

    .i_tile_reorder(tile_reorder),
    .i_tile_reorder_valid(tile_reorder_valid),
    
    .i_tile_enable(tile_enable),
    .i_tile_mode(tile_mode),

    .i_tile_act_thread_id(tile_act_thread_id),
    .i_tile_weight_thread_id(tile_weight_thread_id),

    .i_tile_clear_pe_acc(tile_clear_acc),
    .i_tile_clear_pe_out(tile_clear_out),

    .o_tile_busy(o_tile_busy_bus),

    .i_inv_scale_fixed_point(tile_scale),
    .i_zero_point(tile_zero_point),

    .i_relu_data_valid(tile_relu),

    .o_read_data(o_read_data),

    .i_core_output_select(core_output_select)
);

endmodule
