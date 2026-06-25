module Row_Bufferv2 #(
    parameter BUFFER_ID = 0,
    parameter ELEMENT_WIDTH = 8,
    parameter IDX_WIDTH = 2,
    parameter SPARSE_MODE_WIDTH = 2,
    parameter I_DATA_WIDTH = 32
)(

    input clk,

    input [I_DATA_WIDTH-1:0] i_data,

    input i_put_data,
    input i_shift,
    input [SPARSE_MODE_WIDTH-1:0]i_mode,
    
    output [ELEMENT_WIDTH-1:0] o_systolic_data,
    output [IDX_WIDTH-1:0] o_systolic_index,
    output [I_DATA_WIDTH-1:0] o_simd_data
);

localparam INST_NUM = I_DATA_WIDTH / ELEMENT_WIDTH;


reg [ELEMENT_WIDTH*(INST_NUM-1)-1:0] element_buffer;  // 3 elements
reg [IDX_WIDTH*INST_NUM-1:0] index_or_element_buffer; // 4 indices or 1 elements

// i_put_data: Load new data into the buffer for SIMD or Systolic mode
// i_shift: Shift the buffer to the right by one element
// i_mode: 2'b11 means dense systolic mode, otherwise sparse mode

always @(posedge clk) begin
        
    if (i_put_data) begin
            
        element_buffer <= i_data[ELEMENT_WIDTH*(INST_NUM-1)-1:0];
        index_or_element_buffer <= i_data[I_DATA_WIDTH-1:I_DATA_WIDTH-IDX_WIDTH*INST_NUM];

    end else if (i_shift) begin

        if (i_mode == 2'b11) begin

            element_buffer <= {index_or_element_buffer, element_buffer[ELEMENT_WIDTH*(INST_NUM-1)-1:ELEMENT_WIDTH]};
            index_or_element_buffer <= 0 ;

        end else begin

            element_buffer <= {{ELEMENT_WIDTH{1'b0}}, element_buffer[ELEMENT_WIDTH*(INST_NUM-1)-1:ELEMENT_WIDTH]};
            index_or_element_buffer <= {{IDX_WIDTH{1'b0}}, index_or_element_buffer[IDX_WIDTH*(INST_NUM-1)-1:IDX_WIDTH]};

        end

    end

end

assign o_systolic_data = element_buffer[ELEMENT_WIDTH-1:0];
assign o_systolic_index = index_or_element_buffer[IDX_WIDTH-1:0];

assign o_simd_data = {index_or_element_buffer, element_buffer};

endmodule