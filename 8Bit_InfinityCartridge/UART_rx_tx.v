`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/30/2025 05:13:03 PM
// Design Name: 
// Module Name: UART_rx
// Project Name: 
// Target Devices: 
//////////////////////////////////////////////////////////////////////////////////


module UART_rx_tx(
    input clk,               // 100 MHz
    input rst,               // Active-high reset
    input rxd,               // From ESP32
    input transmit_trigger,  // Signal to start transmission
    output reg txd,          // To USB-UART
    output reg [2:0] leds,   // RGB LEDs
    output reg transmitting  // Active during transmission
);

    // UART Parameters
    parameter CLK_FREQ = 100_000_000;
    parameter BAUD = 115200;
    localparam CYCLES_PER_BIT = CLK_FREQ/BAUD;
    localparam SAMPLE_POINT = CYCLES_PER_BIT/2;
    
    // FSM States - binary encoding
    parameter [2:0] 
        IDLE     = 3'b000,
        RX_START = 3'b001,
        RX_DATA  = 3'b010,
        RX_STOP  = 3'b011,
        TX_START = 3'b100,
        TX_DATA  = 3'b101,
        TX_STOP  = 3'b110,
        ERROR    = 3'b111;
    
    reg [2:0] state = IDLE;
    reg [15:0] cycle_counter = 0;
    reg [2:0] bit_index = 0;
    reg [7:0] rx_byte = 0;
    reg [7:0] tx_byte = 0;
    
    // FIFO Instance
    wire fifo_empty, fifo_full;
    reg fifo_wr_en, fifo_rd_en;
    wire [7:0] fifo_rd_data;
    
    UART_FIFO #(
        .BUFFER_SIZE(143360), // 140KB buffer
        .PTR_SIZE(18)       // log2(143360) = 18-bit pointers
    ) fifo (
        .clk(clk),
        .rst(rst),
        .wr_en(fifo_wr_en),
        .rd_en(fifo_rd_en),
        .wr_data(rx_byte),
        .rd_data(fifo_rd_data),
        .empty(fifo_empty),
        .full(fifo_full)
    );
    
    // Input synchronization
    reg [2:0] rxd_sync = 3'b111;
    reg [2:0] trigger_sync = 3'b000;
    always @(posedge clk) begin
        rxd_sync <= {rxd_sync[1:0], rxd};
        trigger_sync <= {trigger_sync[1:0], transmit_trigger};
    end
    wire clean_rxd = rxd_sync[2];
    wire trigger_rising = (trigger_sync[2:1] == 2'b01);
    
    // Main State Machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            txd <= 1'b1;
            cycle_counter <= 0;
            bit_index <= 0;
            fifo_wr_en <= 0;
            fifo_rd_en <= 0;
            transmitting <= 0;
            leds <= 3'b001;
        end else begin
            case (state)
                IDLE: begin
                    leds <= 3'b001; // Red
                    transmitting <= 0;
                    fifo_wr_en <= 0;
                    fifo_rd_en <= 0;
                    
                    if (!clean_rxd) begin
                        state <= RX_START;
                        cycle_counter <= 1;
                        bit_index <= 0;
                    end
                    else if (trigger_rising && !fifo_empty) begin
                        state <= TX_START;
                        fifo_rd_en <= 1;
                        transmitting <= 1;
                        cycle_counter <= 0;
                    end
                end
                
                RX_START: begin
                    leds <= 3'b100; // Blue
                    if (cycle_counter == SAMPLE_POINT) begin
                        if (clean_rxd) state <= ERROR;
                        else begin
                            state <= RX_DATA;
                            cycle_counter <= 0;
                        end
                    end else cycle_counter <= cycle_counter + 1;
                end
                
                RX_DATA: begin
                    if (cycle_counter == SAMPLE_POINT)
                        rx_byte[bit_index] <= clean_rxd;
                    
                    if (cycle_counter == CYCLES_PER_BIT - 1) begin
                        cycle_counter <= 0;
                        bit_index <= bit_index + 1;
                        if (bit_index == 3'd7) state <= RX_STOP;
                    end else cycle_counter <= cycle_counter + 1;
                end
                
                RX_STOP: begin
                    if (cycle_counter == SAMPLE_POINT) begin
                        if (!clean_rxd) state <= ERROR;
                        else if (!fifo_full) begin
                            fifo_wr_en <= 1;
                            leds <= 3'b010; // Green
                            state <= IDLE;
                        end
                    end else cycle_counter <= cycle_counter + 1;
                end
                
                TX_START: begin
                    fifo_rd_en <= 0;
                    leds <= 3'b110; // Yellow
                    tx_byte <= fifo_rd_data;
                    txd <= 1'b0;
                    if (cycle_counter == CYCLES_PER_BIT - 1) begin
                        state <= TX_DATA;
                        bit_index <= 0;
                        cycle_counter <= 0;
                    end else cycle_counter <= cycle_counter + 1;
                end
                
                TX_DATA: begin
                    txd <= tx_byte[bit_index];
                    if (cycle_counter == CYCLES_PER_BIT - 1) begin
                        cycle_counter <= 0;
                        bit_index <= bit_index + 1;
                        if (bit_index == 3'd7) state <= TX_STOP;
                    end else cycle_counter <= cycle_counter + 1;
                end
                
                TX_STOP: begin
                    txd <= 1'b1;
                    if (cycle_counter == CYCLES_PER_BIT - 1) begin
                        cycle_counter <= 0;
                        if (!fifo_empty) begin
                            fifo_rd_en <= 1;
                            state <= TX_START;
                        end else begin
                            transmitting <= 0;
                            state <= IDLE;
                        end
                    end else cycle_counter <= cycle_counter + 1;
                end
                
                ERROR: begin
                    leds <= 3'b101; // Purple
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
