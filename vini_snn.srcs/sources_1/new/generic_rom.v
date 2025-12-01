`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/15 14:50:31
// Design Name: 
// Module Name: generic_rom
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module generic_rom
#(
        parameter ADDR_WIDTH = 10,
        parameter DATA_WIDTH = 16,
        parameter INIT_FILE = "W1.mem"
)
(
    input clk,
    input [(ADDR_WIDTH-1):0] addr,
    output reg [(DATA_WIDTH-1):0]  dout
);

    localparam DEPTH = 1 << ADDR_WIDTH;
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    initial begin
        $readmemh(INIT_FILE, mem);
    end
    
    always @(posedge clk) begin
        dout <= mem[addr];
    end
endmodule
