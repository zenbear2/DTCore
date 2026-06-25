`timescale 1 ns / 1 ps

module fifo_fwft_async #(
    parameter DATA_WIDTH = 128,
    parameter ADDR_BITS  = 4   // FIFO Depth = 2^ADDR_BITS (Default 16)
) (
    // Write Interface (wclk domain)
    input  wire                  wclk,
    input  wire                  wrst_n,
    input  wire                  w_en,
    input  wire [DATA_WIDTH-1:0] w_data,
    input  wire                  w_data_valid, // User specific signal
    output wire                  w_full,       // Registered output

    // Read Interface (rclk domain)
    input  wire                  rclk,
    input  wire                  rrst_n,
    input  wire                  r_en,         // Acts as "POP" / "ACK" in FWFT
    output reg  [DATA_WIDTH-1:0] r_data,       // FWFT: Data is always ready
    output wire                  r_data_valid, // FWFT: High if not empty
    output wire                  r_empty       // FWFT: Low if data is ready
);

    // --- Parameters ---
    localparam FIFO_DEPTH = 1 << ADDR_BITS;
    localparam PTR_BITS   = ADDR_BITS + 1; 

    // --- Internal Signals ---
    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    // Pointers (Binary & Gray)
    reg [PTR_BITS-1:0] w_ptr, w_gray;
    reg [PTR_BITS-1:0] r_ptr, r_gray;

    // Next State Signals (Wires)
    wire [PTR_BITS-1:0] w_ptr_next, w_gray_next;
    wire [PTR_BITS-1:0] r_ptr_next, r_gray_next;

    // Synchronizers
    reg [PTR_BITS-1:0] w_gray_sync1, w_gray_sync2; 
    reg [PTR_BITS-1:0] r_gray_sync1, r_gray_sync2;

    // Memory Addresses
    wire [ADDR_BITS-1:0] w_addr;
    wire [ADDR_BITS-1:0] r_addr;

    assign w_addr = w_ptr[ADDR_BITS-1:0];
    assign r_addr = r_ptr[ADDR_BITS-1:0];

    // [FWFT Special] Internal Empty Flag (RAM status)
    wire ram_empty;
    reg  fwft_valid_reg; // Indicates if r_data holds valid data
    wire ren_internal;   // Internal Read Enable for RAM

    // -------------------------------------------------------------------------
    // 1. WRITE DOMAIN LOGIC (wclk) - UNCHANGED
    // -------------------------------------------------------------------------
    assign w_ptr_next = w_ptr + 1'b1;
    assign w_gray_next = w_ptr_next ^ (w_ptr_next >> 1);

    always @(posedge wclk) begin
        if (w_en && w_data_valid && !w_full) begin
            mem[w_addr] <= w_data;
        end
    end

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            w_ptr  <= {PTR_BITS{1'b0}};
            w_gray <= {PTR_BITS{1'b0}};
        end else begin
            if (w_en && w_data_valid && !w_full) begin
                w_ptr       <= w_ptr_next;
                w_gray      <= w_gray_next; 
            end
        end
    end

    // -------------------------------------------------------------------------
    // 2. READ DOMAIN LOGIC (rclk) - MODIFIED FOR FWFT
    // -------------------------------------------------------------------------

    // [FWFT Logic]
    // We read from RAM (update pointer) if:
    // 1. RAM is not empty AND
    // 2. Either output is empty (prefetch) OR User is acknowledging current data (pop)
    assign ren_internal = !ram_empty && (!fwft_valid_reg || r_en);

    assign r_ptr_next = r_ptr + 1'b1;
    assign r_gray_next = r_ptr_next ^ (r_ptr_next >> 1);

    always @(posedge rclk) begin
        if (ren_internal) begin
            r_data <= mem[r_addr]; // Prefetch data to output
        end
    end

    // Pointer Update Logic
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            r_ptr          <= {PTR_BITS{1'b0}};
            r_gray         <= {PTR_BITS{1'b0}};
            fwft_valid_reg <= 1'b0;
        end else begin
            // Update Valid Status
            if (ren_internal) begin
                fwft_valid_reg <= 1'b1; // Data fetched, output is valid
                r_ptr          <= r_ptr_next;
                r_gray         <= r_gray_next;
            end else if (r_en) begin
                // User popped, but RAM was empty, so output becomes invalid
                fwft_valid_reg <= 1'b0; 
            end
        end
    end    

    // -------------------------------------------------------------------------
    // 3. CDC SYNCHRONIZERS - UNCHANGED
    // -------------------------------------------------------------------------
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            w_gray_sync1 <= {PTR_BITS{1'b0}};
            w_gray_sync2 <= {PTR_BITS{1'b0}};
        end else begin
            w_gray_sync1 <= w_gray;
            w_gray_sync2 <= w_gray_sync1;
        end
    end

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            r_gray_sync1 <= {PTR_BITS{1'b0}};
            r_gray_sync2 <= {PTR_BITS{1'b0}};
        end else begin
            r_gray_sync1 <= r_gray;
            r_gray_sync2 <= r_gray_sync1; 
        end
    end

    // -------------------------------------------------------------------------
    // 4. FULL / EMPTY GENERATION
    // -------------------------------------------------------------------------

    assign ram_empty = (r_gray == w_gray_sync2);

    // FWFT Output Interface Flags
    // User sees empty ONLY if the output register is invalid
    assign r_empty      = !fwft_valid_reg; 
    assign r_data_valid = fwft_valid_reg;

    // Full Flag (Same as before)
    // Note: When data moves to output reg, r_ptr increments, so w_full will de-assert 
    // correctly even if data is sitting in output waiting for user.
    assign w_full = (w_gray == {~r_gray_sync2[PTR_BITS-1:PTR_BITS-2], r_gray_sync2[PTR_BITS-3:0]});

endmodule