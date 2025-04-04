`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/03/2025 12:35:41 AM
// Design Name: 
// Module Name: UART_FIFO_tb
// Project Name: 
// Target Devices:  
//////////////////////////////////////////////////////////////////////////////////


module UART_FIFO_tb;
    reg clk = 0;
    reg rst = 1;
    reg wr_en = 0;
    reg rd_en = 0;
    reg [7:0] wr_data;
    wire [7:0] rd_data;
    wire empty, full;
    wire [11:0] debug_count;

    // Declare the FIFO instance
    UART_FIFO #(.BUFFER_SIZE(140*1024), .PTR_SIZE(18)) fifo (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .wr_data(wr_data),
        .rd_data(rd_data),
        .empty(empty),
        .full(full),
        .count(debug_count)
    );

    // Clock generation
    always #5 clk = ~clk;  // 100 MHz clock (10 ns period)

    integer i;
    integer file;
    reg [7:0] data_from_file;

    initial begin
        // Open the binary file for reading
        file = $fopen("random_140kb_file.bin", "rb");
        
        // Wait for the reset to be released
        #10 rst = 0;  // Release reset

        // Write 140KB to FIFO from the file
        for (i = 0; i < 140 * 1024; i = i + 1) begin
            // Read a byte from the file
            if (!$feof(file)) begin
                $fread(data_from_file, file);
                wr_data = data_from_file;
                wr_en = 1;
                #10;
                wr_en = 0;
            end
        end

        // Wait a bit before reading
        #30;

        // Read FIFO completely and display data
        for (i = 0; i < 140 * 1024; i = i + 1) begin
            if (!empty) begin
                rd_en = 1;
                #10;
                rd_en = 0;
            end
        end

        // Close the file
        $fclose(file);

        // Finish the simulation
        #500;
        $finish;
    end
endmodule
