`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/18/2025 05:59:58 PM
// Design Name: 
// Module Name: apple2_wrapper
// Project Name: 
// Target Devices: 
//////////////////////////////////////////////////////////////////////////////////


module apple2_wrapper (
    input clk,
    input reset,
    input cpu,
    output [15:0] cpu_addr,
    output [7:0] cpu_data_out,
    output cpu_we,
    output [15:0] cpu_pc,
    input cpu_irq_n,
    input cpu_nmi_n,

    // Memory interfaces
    input  [7:0] ram_data_in,
    output [7:0] ram_data_out,
    output [15:0] ram_addr,
    output       ram_we,

    // ROM interfaces
    output [10:0] monitor_rom_addr,
    input  [7:0]  monitor_rom_data,
    output [12:0] basic_rom_addr,
    input  [7:0]  basic_rom_data,

    input  [7:0] font_rom_data
);
    // ------------------------------------------------------------------
    // Pipeline ROM address to fix synchronous memory timing
    // ------------------------------------------------------------------
    reg [15:0] cpu_addr_r; // Delayed address for ROM access

    wire [15:0] cpu_addr_internal;
    wire [7:0] cpu_data_out_internal;
    wire       cpu_we_internal;
    wire [15:0] cpu_pc_internal;

    always @(posedge clk) begin
        cpu_addr_r <= cpu_addr_internal; // Delay CPU address for sync ROMs
    end

    // ------------------------------------------------------------------
    // ROM Select (based on delayed address)
    // ------------------------------------------------------------------
    wire monitor_rom_cs = (cpu_addr_r >= 16'hF800);
    wire basic_rom_cs = (cpu_addr_r >= 16'hE000 && cpu_addr_r < 16'hE800);
    wire ram_cs         = (cpu_addr_internal < 16'hC000); // RAM is still sync with current addr

    // ------------------------------------------------------------------
    // CPU
    // ------------------------------------------------------------------
    arlet_6502 cpu_inst (
        .clk(clk),
        .rst(reset),
        .ab(cpu_addr_internal),
        .dbi(
            monitor_rom_cs ? monitor_rom_data :
            basic_rom_cs   ? basic_rom_data   :
            ram_data_in
        ),
        .dbo(cpu_data_out_internal),
        .we(cpu_we_internal),
        .irq_n(cpu_irq_n),
        .nmi_n(cpu_nmi_n),
        .ready(1'b1),
        .pc_monitor(cpu_pc_internal)
    );

    // ------------------------------------------------------------------
    // ROM Address Outputs (use pipelined address)
    // ------------------------------------------------------------------
    assign monitor_rom_addr = cpu_addr_r[10:0];  // For 2KB Monitor ROM
    assign basic_rom_addr   = cpu_addr_r[12:0];  // For 8KB BASIC

    // ------------------------------------------------------------------
    // RAM Control 
    // ------------------------------------------------------------------
    assign ram_we        = cpu_we_internal && ram_cs;
    assign ram_addr      = cpu_addr_internal;
    assign ram_data_out  = cpu_data_out_internal;

    // ------------------------------------------------------------------
    // CPU outputs
    // ------------------------------------------------------------------
    assign cpu_addr      = cpu_addr_internal;
    assign cpu_data_out  = cpu_data_out_internal;
    assign cpu_we        = cpu_we_internal;
    assign cpu_pc        = cpu_pc_internal;

endmodule
