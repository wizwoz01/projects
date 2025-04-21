`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/19/2025 12:34:25 AM
// Design Name: 
// Module Name: apple2_ram
// Project Name: 
// Target Devices: 
//////////////////////////////////////////////////////////////////////////////////


module apple2_ram (
    input wire clk,
    input wire [15:0] address,
    input wire w_en,
    input wire [7:0] din,
    output reg [7:0] dout
);

// 48KB RAM (from $0000-$BFFF)
reg [7:0] memory [0:48*1024-1];
integer i;
always @(posedge clk) begin
    if (w_en && address < 16'hC000) begin
        // Write operation (only to addresses below $C000)
        memory[address[15:0]] <= din;
    end
    // Always read (RAM is synchronous)
    dout <= memory[address[15:0]];
end

// Initialize RAM with zeros (to avoid booting issues)
initial begin
    for ( i = 0; i < 48*1024; i = i + 1) begin
        memory[i] = 8'h00;
    end
end

endmodule
