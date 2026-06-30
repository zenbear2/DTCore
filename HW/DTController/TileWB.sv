module TileWB(

    clk,
    rst_n,

    i_tile_wb_op,       //Sub Decoder out
    i_tile_wb_is_set,   //RFBPCtrl out

    i_tile_dabus,       //instructon out
    i_tile_wb_reorder,  //instructon out
    i_tile_wb_address,  //instructon out
    i_tile_wb_mask,     //instructon out

    o_tile_dabus,
    o_tile_dabus_valid,    

    o_tile_wb_reorder,
    o_tile_wb_reorder_valid,

    o_tile_wb_address,
    o_tile_wb_address_valid,

    o_tile_wb_mask,

    o_tilewb_fifo_full,

    o_error_tile_wb_conflict

);
    
    localparam DABUS_WIDTH = 8;
    localparam REORDER_WIDTH = 8;
    localparam ADDR_WIDTH = 10;
    localparam MASK_WIDTH = 4;
    localparam IS_SET_PORT_WIDTH = 4;

    input clk;
    input rst_n;

    input i_tile_wb_op;

    input [IS_SET_PORT_WIDTH-1 : 0] i_tile_wb_is_set;

    input [DABUS_WIDTH-1 : 0] i_tile_dabus;
    input [REORDER_WIDTH-1 : 0] i_tile_wb_reorder;
    input [ADDR_WIDTH-1 : 0] i_tile_wb_address;
    input [MASK_WIDTH-1 : 0] i_tile_wb_mask;

    output [DABUS_WIDTH-1 : 0] o_tile_dabus;
    output o_tile_dabus_valid;

    output [REORDER_WIDTH-1 : 0] o_tile_wb_reorder;
    output o_tile_wb_reorder_valid;

    output [ADDR_WIDTH-1 : 0] o_tile_wb_address;
    output o_tile_wb_address_valid;

    output [MASK_WIDTH-1 : 0] o_tile_wb_mask;

    output o_tilewb_fifo_full;

    output o_error_tile_wb_conflict;

    wire reorder_valid;

    wire reorder_full;
    wire reorder_empty;

    wire wb_address_valid;
    wire wb_address_full;
    wire wb_address_empty;
    wire tile_wb_is_set;

    reg [DABUS_WIDTH-1 : 0] tile_dabus_reg;
    reg tile_dabus_valid_reg;

    reg tile_wb_delay_0;
    reg tile_wb_delay_1;

    assign o_tile_dabus = tile_dabus_reg;
    assign o_tile_dabus_valid = tile_dabus_valid_reg;

    assign o_tile_wb_reorder_valid = tile_wb_delay_0 & reorder_valid;
    assign o_tile_wb_address_valid = tile_wb_delay_1 & wb_address_valid;

    assign o_tilewb_fifo_full = reorder_full | wb_address_full;

    assign tile_wb_is_set = |i_tile_wb_is_set;

    assign o_error_tile_wb_conflict = (o_tile_wb_address_valid)? (~tile_wb_is_set) : 1'b0;

    always @(posedge clk) begin
        if(!rst_n) begin
            tile_dabus_reg <= 0;
            tile_dabus_valid_reg <= 0;

            tile_wb_delay_0 <= 0;
            tile_wb_delay_1 <= 0;
        end
        else begin
            tile_dabus_reg <= (i_tile_wb_op)? i_tile_dabus : tile_dabus_reg;
            tile_dabus_valid_reg <= i_tile_wb_op;

            tile_wb_delay_0 <= tile_dabus_valid_reg;
            tile_wb_delay_1 <= tile_wb_delay_0;
        end
    end

    fifo_sync #(
        .ADDR_WIDTH(2),
        .DWIDTH(REORDER_WIDTH)
    ) Tile_WB_Reorder_FIFO (
        .rst_n      (rst_n),
        .clk        (clk),
        .wr_en      (i_tile_wb_op),
        .rd_en      (tile_dabus_valid_reg),
        .din        (i_tile_wb_reorder),
        .dout       (o_tile_wb_reorder),
        .empty      (reorder_empty),
        .full       (reorder_full),
        .data_valid (reorder_valid)
    );

    fifo_sync #(
        .ADDR_WIDTH(2),
        .DWIDTH(ADDR_WIDTH)
    ) Tile_WB_Address_FIFO (
        .rst_n      (rst_n),
        .clk        (clk),
        .wr_en      (i_tile_wb_op),
        .rd_en      (reorder_valid),
        .din        (i_tile_wb_address),
        .dout       (o_tile_wb_address),
        .empty      (wb_address_empty),
        .full       (wb_address_full),
        .data_valid (wb_address_valid)
    );

    fifo_sync #(  //When used together with wb_address
        .ADDR_WIDTH(2),
        .DWIDTH(MASK_WIDTH)
    ) Tile_MASK_FIFO (
        .rst_n      (rst_n),
        .clk        (clk),
        .wr_en      (i_tile_wb_op),
        .rd_en      (reorder_valid),
        .din        (i_tile_wb_mask),
        .dout       (o_tile_wb_mask),
        .empty      (),
        .full       (),
        .data_valid ()
    );    


endmodule