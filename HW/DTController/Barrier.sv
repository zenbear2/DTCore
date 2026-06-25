module Barrier #(
    parameter SLOT_ID  = 5
)(    

    i_block_sync_op,

    i_sync_req,
    i_wait_agu_slot,
    i_wait_tile,
    i_status,

    i_agu_slot_ready,
    i_tile_busy,

    i_core_busy,
    i_ext_busy,

    i_rfbpctrl_stall,

    o_status,
    o_busy,
    o_fetch

);
    localparam SYNC_REQ_WIDTH  = 5;
    localparam CORE_SYNC_WIDTH = 4;
    localparam STATUS_WIDTH = 6;
    localparam NUM_INTERNAL_SLOTS = 2; 

    // Inputs
    input                            i_block_sync_op;
    // From Instruction
    input [SYNC_REQ_WIDTH-1:0]       i_sync_req;
    input [NUM_INTERNAL_SLOTS-1:0]   i_wait_agu_slot;
    input                            i_wait_tile;
    input [STATUS_WIDTH-1:0]         i_status;
    // From Units
    input [NUM_INTERNAL_SLOTS-1:0]   i_agu_slot_ready;
    input                            i_tile_busy;
    // From Core
    input [CORE_SYNC_WIDTH-1:0]      i_core_busy;
    input                            i_ext_busy;

    input                            i_rfbpctrl_stall;

    // Outputs
    output [STATUS_WIDTH-1:0]        o_status;
    output                           o_busy;
    output                           o_fetch;

    wire  [NUM_INTERNAL_SLOTS-1:0]   agu_slot_busy = ~i_agu_slot_ready; // ready mean slot is empty

    wire  [2:0] intinal_waits;
    wire  [2:0] initial_busys;
    wire        intinal_check_n; // 0: ok to proceed, 1: need to wait

    wire  [SYNC_REQ_WIDTH-1:0] busy_in = {i_ext_busy, i_core_busy};
    wire  [SYNC_REQ_WIDTH-1:0] busy_align; 
    wire                       sync_check_n;
    wire w_barrier_active;

    // Initial check for own slot
    assign intinal_waits  = {i_wait_tile, i_wait_agu_slot};
    assign initial_busys  = {i_tile_busy, agu_slot_busy};
    assign intinal_check_n  = |(intinal_waits & initial_busys);

    // Sync check from other slots
    genvar i;
    generate
        for(i=0; i<SYNC_REQ_WIDTH; i=i+1) begin : GEN_BARRIER_SLOT
            if(i != SLOT_ID) begin : GEN_OTHER_SLOTS
                assign busy_align[i] = i_sync_req[i] & busy_in[i];
            end
            else begin : GEN_OWN_SLOT
                assign busy_align[i] = 1'b0;
            end
        end
    endgenerate

    assign sync_check_n = |(busy_align);

    assign o_status = i_status;

    assign o_busy = intinal_check_n;

    assign w_barrier_active = i_block_sync_op && (intinal_check_n || sync_check_n);
    assign o_fetch = !(i_rfbpctrl_stall || w_barrier_active);

endmodule

