module Column_Bufferv2 #(
    parameter BUFFER_ID = 0,
    parameter I_DATA_WIDTH = 32
)(

    input clk,

    input [I_DATA_WIDTH-1:0] i_data,

    input i_put_data,
    
    output [I_DATA_WIDTH-1:0] o_data
);

reg [I_DATA_WIDTH-1:0] buffer;

always @(posedge clk) begin
    if (i_put_data) begin

        buffer <= i_data;
    end
end

assign o_data = buffer;

endmodule