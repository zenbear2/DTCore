module fifo_async #(
    parameter DATA_WIDTH = 128,
    parameter ADDR_BITS  = 4   // FIFO Depth = 2^ADDR_BITS (Default 256)
) (
    // Write Interface (wclk domain)
    input  wire                  wclk,
    input  wire                  wrst_n,
    input  wire                  w_en,
    input  wire [DATA_WIDTH-1:0] w_data,
    input  wire                  w_data_valid, // User specific signal
    output wire                  w_full,       // Registered output for better timing

    // Read Interface (rclk domain)
    input  wire                  rclk,
    input  wire                  rrst_n,
    input  wire                  r_en,
    output reg [DATA_WIDTH-1:0]  r_data,
    output reg                   r_data_valid,
    output wire                  r_empty       // Registered output for better timing
);

    // --- Parameters ---
    localparam FIFO_DEPTH = 1 << ADDR_BITS;
    localparam PTR_BITS   = ADDR_BITS + 1; // N+1 bits for Full/Empty distinction

    // --- Internal Signals ---
    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    // Pointers (Binary & Gray)
    reg [PTR_BITS-1:0] w_ptr, w_gray;
    reg [PTR_BITS-1:0] r_ptr, r_gray;

    // Next State Signals (Wires)
    wire [PTR_BITS-1:0] w_ptr_next, w_gray_next;
    wire [PTR_BITS-1:0] r_ptr_next, r_gray_next;

    // Synchronizers
    reg [PTR_BITS-1:0] w_gray_sync1, w_gray_sync2; // w_gray synced to rclk
    reg [PTR_BITS-1:0] r_gray_sync1, r_gray_sync2; // r_gray synced to wclk

    // Memory Addresses
    wire [ADDR_BITS-1:0] w_addr;
    wire [ADDR_BITS-1:0] r_addr;

    assign w_addr = w_ptr[ADDR_BITS-1:0];
    assign r_addr = r_ptr[ADDR_BITS-1:0];

    // -------------------------------------------------------------------------
    // 1. WRITE DOMAIN LOGIC (wclk)
    // -------------------------------------------------------------------------
    
    // Binary Next Calculation
    assign w_ptr_next = w_ptr + 1'b1;
    
    // Gray Code Next Calculation (Binary to Gray: (n >> 1) ^ n)
    // Calculated *before* the register to ensure the register output is glitch-free
    assign w_gray_next = w_ptr_next ^ (w_ptr_next >> 1);

    // Write Logic & Pointer Update

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
            // Only write if enabled, data is valid, and FIFO is not full
            if (w_en && w_data_valid && !w_full) begin
                w_ptr       <= w_ptr_next;
                w_gray      <= w_gray_next; // Registered Gray Code Output
            end
        end
    end

    // -------------------------------------------------------------------------
    // 2. READ DOMAIN LOGIC (rclk)
    // -------------------------------------------------------------------------

    // Binary Next Calculation
    assign r_ptr_next = r_ptr + 1'b1;

    // Gray Code Next Calculation
    assign r_gray_next = r_ptr_next ^ (r_ptr_next >> 1);

    // Read Logic & Pointer Update
    always @(posedge rclk) begin
        if (r_en && !r_empty) begin
            r_data <= mem[r_addr]; 
        end
    end

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            r_ptr        <= {PTR_BITS{1'b0}};
            r_gray       <= {PTR_BITS{1'b0}};
            r_data_valid <= 1'b0;
        end else begin
            // Only read if enabled and FIFO is not empty
            if (r_en && !r_empty) begin
                r_ptr        <= r_ptr_next;
                r_gray       <= r_gray_next; // Registered Gray Code Output
                r_data_valid <= 1'b1;
            end else begin
                r_data_valid <= 1'b0;
            end
        end
    end    

    // -------------------------------------------------------------------------
    // 3. CDC SYNCHRONIZERS
    // -------------------------------------------------------------------------

    // Sync Write Pointer to Read Domain (w_gray -> rclk)
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            w_gray_sync1 <= {PTR_BITS{1'b0}};
            w_gray_sync2 <= {PTR_BITS{1'b0}};
        end else begin
            w_gray_sync1 <= w_gray;
            w_gray_sync2 <= w_gray_sync1; // Stable pointer for empty check
        end
    end

    // Sync Read Pointer to Write Domain (r_gray -> wclk)
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            r_gray_sync1 <= {PTR_BITS{1'b0}};
            r_gray_sync2 <= {PTR_BITS{1'b0}};
        end else begin
            r_gray_sync1 <= r_gray;
            r_gray_sync2 <= r_gray_sync1; // Stable pointer for full check
        end
    end

    // -------------------------------------------------------------------------
    // 4. FULL / EMPTY GENERATION
    // -------------------------------------------------------------------------

    // EMPTY Condition (rclk domain): r_gray == w_gray_sync2
    assign r_empty = (r_gray == w_gray_sync2);

    // FULL Condition (wclk domain): 
    // MSB != MSB, 2nd MSB != 2nd MSB, Rest LSBs == Rest LSBs
    assign w_full = (w_gray == {~r_gray_sync2[PTR_BITS-1:PTR_BITS-2], r_gray_sync2[PTR_BITS-3:0]});

endmodule