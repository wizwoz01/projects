module apple2 (
    input clk,                // 125 MHz input clock
    input rst,                // Active-high reset
    input rxd,                // UART receive data
    input key,
    output [2:0] leds,        // Loading status LEDs
    // HDMI outputs
    output hdmi_clk_n,
    output hdmi_clk_p,
    output [2:0] hdmi_data_n,
    output [2:0] hdmi_data_p,
    output [2:0] led
);

//
// 1. Clock Generation
//
wire pix_clk;    // 25.175 MHz pixel clock (used for video read)
wire pix_clk_5x; // 125 MHz pixel clock 5x version (used for UART write)
wire locked;

clk_wiz_0_clk_wiz clock_gen (
    .clk_out1(pix_clk),
    .clk_out2(pix_clk_5x),
    .resetn(~rst),
    .locked(locked),
    .clk_in1(clk)
);

wire [15:0] cpu_addr;
wire [7:0]  cpu_data_in;
wire [7:0]  cpu_data_out;
wire        cpu_we;
wire [15:0] cpu_pc;
wire [7:0] cpu_vram_out;

//
// CPU wrapper
//
arlet_6502 cpu (
    .clk(pix_clk),            
    .enable(1'b1),            // always run
    .rst(rst),
    .ab(cpu_addr),
    .dbi(cpu_data_in),
    .dbo(cpu_data_out),
    .we(cpu_we), // Only write to video memory space
    .irq_n(1'b1),             // no interrupts for now
    .nmi_n(1'b1),
    .ready(1'b1),
    .pc_monitor(cpu_pc)
);

assign led[2:0] = cpu_pc[15:13]; // show top bits of PC on LEDs

// Memory decode
wire ram_cs      = (cpu_addr < 16'hC000);               // $0000-$BFFF
wire basic_cs    = (cpu_addr >= 16'hE000);              // $E000-$FFFF (BASIC ROM)
wire screen_cs   = (cpu_addr >= 16'h0400 && cpu_addr < 16'h0800);  // $0400-$07FF for screen memory


//
// 2. Dual-Port BRAM for Disk Image Storage
//
// Port A: Write port (UART side)
// Port B: Read port (Video side)
//
wire [17:0] disk_addr;
wire [7:0]  disk_data;
wire        disk_we;

//// Video port signals
wire [17:0] video_addr;
wire [7:0]  video_data;
wire        video_en;

wire [7:0]  video_mem_data;

////  Video System with Dual-Port BRAM Read Interface
////
wire hs, vs, de, frame;
wire signed [15:0] sx, sy;
assign video_en = de && (sy < 480) && (sx < 640);

// Ensure CPU writes to video memory are handled
assign cpu_vram_out = (cpu_we && (cpu_addr >= 16'h0400 && cpu_addr <= 16'h07FF)) ? cpu_data_out : 8'hFF; // If CPU is writing, use cpu_data_out


disk_image dual_port_inst (
    // Port A: CPU
    .clka(pix_clk),
    .ena(1'b1),
    .wea(cpu_we && (cpu_addr >= 16'h0400 && cpu_addr <= 16'h07FF)),
    .addra(cpu_addr[12:0]),
    .dina(cpu_data_out),
    .douta(cpu_vram_out),  // Write to video memory

    // Port B: HDMI renderer (video output)
    .clkb(pix_clk),
    .enb(video_en),
    .web(1'b0),
    .addrb(video_addr[12:0]),
    .doutb(video_data) // Read from video memory for rendering
);


// Memory Mapping
reg [7:0] rom_dout_raw;
wire [7:0] rom_out;
rom #(8,16) roms (
    .clock(pix_clk),
	.ce(1'b1),
	.a(cpu_addr),
	.data_out(rom_out)
);

wire [7:0] monitor_data;
apple2_rom_monitor rom_monitor (
    .clk(pix_clk),
    .addr(cpu_addr),
    .data(monitor_data)
);

always @(*) begin
    case (cpu_addr[15:11])
        5'b11110: rom_dout_raw = rom_out;   // $E000-$E7FF
        5'b11111: rom_dout_raw = monitor_data;     // $F800-$FFFF
        default:  rom_dout_raw = 8'hFF;            // unmapped space returns 0xFF
    endcase
end

// Memory space for ROM (Basic and Monitor ROMs)
wire rom_cs = (cpu_addr >= 16'hE000 && cpu_addr <= 16'hE7FF) || 
              (cpu_addr >= 16'hF800 && cpu_addr <= 16'hFFFF);

//
// FONT ROM for text rendering (Characters)
//
wire [7:0] char_rom_data;
font_rom font (
    .clk(pix_clk),
    .addr({video_data, sy[2:0]}),
    .data(char_rom_data)
);


// One-Button Keyboard
wire [7:0] kb_data;
fake_keyboard kb (
    .clk(pix_clk),
    .rst(rst),
    .switch(key),
    .addr(cpu_addr),
    .strobe(!cpu_we),
    .kb_data(kb_data)
);

// RAM (Normal RAM - $0000-$BFFF)
wire ram_write_en = cpu_we && ram_cs;
wire [15:0] ram_addr = cpu_addr;
wire [7:0]  ram_din = cpu_data_out;

// RAM instance
apple2_ram my_ram (
    .clk(pix_clk),
    .address(ram_addr),
    .w_en(ram_write_en),
    .din(ram_din),
    .dout(ram_dout)
);

// Data routing 
assign cpu_data_in =
    rom_cs                 ? rom_dout_raw     :    // ROM
    screen_cs              ? cpu_vram_out     :    // Video memory access
    (cpu_addr == 16'hC000 || cpu_addr == 16'hC010) ? kb_data : // Keyboard data
                            ram_dout;  // RAM data


// UART Receiver
wire load_complete;
apple2_dsk_UART uart_rx (
    .clk(pix_clk_5x),
    .rst(rst),
    .rxd(rxd),
    .status_leds(leds),
    .disk_addr(disk_addr),
    .disk_data(disk_data),
    .disk_wr_en(disk_we),
    .load_complete(load_complete)
);

//
// Display Timings
//
display_timings timings (
    .i_pix_clk(pix_clk),
    .i_rst(rst),
    .o_hs(hs),
    .o_vs(vs),
    .o_de(de),
    .o_frame(frame),
    .o_sx(sx),
    .o_sy(sy)
);

wire [5:0] column = (sx[8:3] > 6'd39) ? 6'd39 : sx[8:3];
assign video_addr = 1024 + ((sy[2:0] << 7) + (sy[8:6] * 40)) + column;

// HDMI Output Generation (VGA-to-HDMI)
reg [7:0] vga_r, vga_g, vga_b;

always @(posedge pix_clk) begin
    if (de && (sy < 480) && (sx < 640)) begin
        if (!load_complete) begin
            vga_r <= 8'h70;
            vga_g <= 8'hFF;
            vga_b <= 8'h70;
        end else begin
            if (char_rom_data[7 - sx[2:0]]) begin
                vga_r <= 8'hFF;
                vga_g <= 8'hFF;
                vga_b <= 8'hFF;
            end else begin
                vga_r <= 8'h30;
                vga_g <= 8'hC0;
                vga_b <= 8'h30;
            end
        end
    end else begin
        vga_r <= 8'h00;
        vga_g <= 8'h00;
        vga_b <= 8'h00;
    end
end

wire tmds_ch0_serial, tmds_ch1_serial, tmds_ch2_serial, tmds_chc_serial;
hdmi hdmi_out (
    .i_pix_clk(pix_clk),
    .i_pix_clk_5x(pix_clk_5x),
    .i_rst(!locked),
    .i_de(de),
    .i_data_ch0(vga_b),
    .i_data_ch1(vga_g),
    .i_data_ch2(vga_r),
    .i_ctrl_ch0({vs, hs}),
    .i_ctrl_ch1(2'b00),
    .i_ctrl_ch2(2'b00),
    .o_tmds_ch0_serial(tmds_ch0_serial),
    .o_tmds_ch1_serial(tmds_ch1_serial),
    .o_tmds_ch2_serial(tmds_ch2_serial),
    .o_tmds_chc_serial(tmds_chc_serial)
);

OBUFDS #(.IOSTANDARD("TMDS_33")) tmds_buf_ch0 (.I(tmds_ch0_serial), .O(hdmi_data_p[0]), .OB(hdmi_data_n[0]));
OBUFDS #(.IOSTANDARD("TMDS_33")) tmds_buf_ch1 (.I(tmds_ch1_serial), .O(hdmi_data_p[1]), .OB(hdmi_data_n[1]));
OBUFDS #(.IOSTANDARD("TMDS_33")) tmds_buf_ch2 (.I(tmds_ch2_serial), .O(hdmi_data_p[2]), .OB(hdmi_data_n[2]));
OBUFDS #(.IOSTANDARD("TMDS_33")) tmds_buf_chc (.I(tmds_chc_serial), .O(hdmi_clk_p), .OB(hdmi_clk_n));

endmodule

