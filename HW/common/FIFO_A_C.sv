module fifo_async_count #(
    parameter DATA_WIDTH = 128,
    parameter ADDR_BITS  = 4   // Depth = 256
) (
    // Write Interface (wclk domain)
    input  wire                  wclk,
    input  wire                  wrst_n,
    input  wire                  w_en,
    input  wire [DATA_WIDTH-1:0] w_data,
    input  wire                  w_data_valid,
    output reg                   w_full,
    output wire [ADDR_BITS:0]    w_usage, // New: Write side count

    // Read Interface (rclk domain)
    input  wire                  rclk,
    input  wire                  rrst_n,
    input  wire                  r_en,
    output reg [DATA_WIDTH-1:0]  r_data,
    output reg                   r_data_valid,
    output reg                   r_empty,
    output wire [ADDR_BITS:0]    r_usage  // New: Read side count
);

    // --- Parameters ---
    localparam FIFO_DEPTH = 1 << ADDR_BITS;
    localparam PTR_BITS   = ADDR_BITS + 1; 

    // --- Internal Signals ---
    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];
    
    reg [PTR_BITS-1:0] w_ptr, w_gray;
    reg [PTR_BITS-1:0] r_ptr, r_gray;
    
    wire [PTR_BITS-1:0] w_ptr_next, w_gray_next;
    wire [PTR_BITS-1:0] r_ptr_next, r_gray_next;

    reg [PTR_BITS-1:0] w_gray_sync1, w_gray_sync2; 
    reg [PTR_BITS-1:0] r_gray_sync1, r_gray_sync2;

    wire [ADDR_BITS-1:0] w_addr = w_ptr[ADDR_BITS-1:0];
    wire [ADDR_BITS-1:0] r_addr = r_ptr[ADDR_BITS-1:0];

    // -------------------------------------------------------------------------
    // 1. MEMORY (BRAM Inference: No Async Reset on RAM)
    // -------------------------------------------------------------------------
    always @(posedge wclk) begin
        if (w_en && w_data_valid && !w_full) begin
            mem[w_addr] <= w_data;
        end
    end

    // -------------------------------------------------------------------------
    // 2. WRITE DOMAIN CONTROL (wclk)
    // -------------------------------------------------------------------------
    assign w_ptr_next  = w_ptr + 1'b1;
    assign w_gray_next = w_ptr_next ^ (w_ptr_next >> 1);

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            w_ptr  <= {PTR_BITS{1'b0}};
            w_gray <= {PTR_BITS{1'b0}};
        end else begin
            if (w_en && w_data_valid && !w_full) begin
                w_ptr  <= w_ptr_next;
                w_gray <= w_gray_next;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 3. READ DOMAIN CONTROL (rclk) & Data Output
    // -------------------------------------------------------------------------
    assign r_ptr_next  = r_ptr + 1'b1;
    assign r_gray_next = r_ptr_next ^ (r_ptr_next >> 1);

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            r_ptr        <= {PTR_BITS{1'b0}};
            r_gray       <= {PTR_BITS{1'b0}};
            r_data_valid <= 1'b0;
            // No r_data reset here for BRAM inference
        end else begin
            if (r_en && !r_empty) begin
                r_ptr        <= r_ptr_next;
                r_gray       <= r_gray_next;
                r_data_valid <= 1'b1;
                r_data       <= mem[r_addr]; // Sync read
            end else begin
                r_data_valid <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 4. CDC SYNCHRONIZERS
    // -------------------------------------------------------------------------
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) {w_gray_sync2, w_gray_sync1} <= 0;
        else         {w_gray_sync2, w_gray_sync1} <= {w_gray_sync1, w_gray};
    end

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) {r_gray_sync2, r_gray_sync1} <= 0;
        else         {r_gray_sync2, r_gray_sync1} <= {r_gray_sync1, r_gray};
    end

    // -------------------------------------------------------------------------
    // 5. FULL / EMPTY LOGIC
    // -------------------------------------------------------------------------
    always @(*) r_empty = (r_gray == w_gray_sync2);
    
    wire w_full_val = (w_gray == {~r_gray_sync2[PTR_BITS-1:PTR_BITS-2], r_gray_sync2[PTR_BITS-3:0]});
    always @(*) w_full = w_full_val;

    // -------------------------------------------------------------------------
    // 6. USAGE COUNTS (Gray -> Binary -> Subtraction)
    // -------------------------------------------------------------------------
    reg [PTR_BITS-1:0] r_ptr_sync_bin;
    reg [PTR_BITS-1:0] w_ptr_sync_bin;
    integer i;

    // Write Domain Usage (w_usage = w_ptr - synced_r_ptr)
    always @(*) begin
        r_ptr_sync_bin[PTR_BITS-1] = r_gray_sync2[PTR_BITS-1];
        for (i = PTR_BITS-2; i >= 0; i = i - 1)
            r_ptr_sync_bin[i] = r_ptr_sync_bin[i+1] ^ r_gray_sync2[i];
    end
    assign w_usage = w_ptr - r_ptr_sync_bin;

    // Read Domain Usage (r_usage = synced_w_ptr - r_ptr)
    always @(*) begin
        w_ptr_sync_bin[PTR_BITS-1] = w_gray_sync2[PTR_BITS-1];
        for (i = PTR_BITS-2; i >= 0; i = i - 1)
            w_ptr_sync_bin[i] = w_ptr_sync_bin[i+1] ^ w_gray_sync2[i];
    end
    assign r_usage = w_ptr_sync_bin - r_ptr;

endmodule