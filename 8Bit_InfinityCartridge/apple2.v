//TOP
module apple2 (
    input clk,                // 125 MHz input clock
    input rst,                // Active-high reset
    input switch,
    output [2:0] led,         // Status LEDs
    // HDMI outputs
    output hdmi_clk_n,
    output hdmi_clk_p,
    output [2:0] hdmi_data_n,
    output [2:0] hdmi_data_p
);

//
// 1. Clock Generation
//
wire pix_clk;    // 25.175 MHz pixel clock
wire pix_clk_5x; // 125 MHz pixel clock 5x
wire locked;

clk_wiz_0_clk_wiz clock_gen (
    .clk_out1(pix_clk),
    .clk_out2(pix_clk_5x),
    .resetn(~rst),
    .locked(locked),
    .clk_in1(clk)
);

wire [7:0] video_data;
//
// 2. Memory Components
//
// Monitor ROM (Apple II firmware) - 2KB at $F800-$FFFF
wire [10:0] monitor_rom_addr;
wire [7:0] monitor_rom_data;
monitor_rom #(8,11) monitor (
	   .clock(pix_clk),
	   .ce(1'b1),
	   .a(monitor_ram_addr),
	   .data_out(monitor_rom_data)
   );  

// BASIC ROM - ?KB at $E000-$E7FF 
wire [10:0] basic_rom_addr; 
wire [7:0] basic_rom_data;
rom #(8,11) roms (
	   .clock(pix_clk),
	   .ce(1'b1),
	   .a(basic_rom_addr),
	   .data_out(basic_rom_data)
   );  

// Font ROM - 2KB
wire [10:0] font_rom_addr;
wire [7:0] font_rom_data;
font_rom apple2_font_rom (
    .clk(pix_clk),
    .addr(font_rom_addr),
    .data(font_rom_data)
);
// Main UNIFIED RAM instance (48KB)
wire [15:0] ram_addr;
wire [7:0] ram_out;
wire ram_we;
wire [7:0] cpu_data_out;

apple2_ram main_ram (
    .clk(pix_clk),
    .address(ram_addr),
    .w_en(ram_we),
    .din(cpu_data_out),
    .dout(ram_out)
);

//
// 3. CPU System
//
wire [15:0] cpu_addr;
wire cpu_we;
wire [15:0] cpu_pc;

apple2_wrapper cpu_wrapper (
    .clk(pix_clk),
    .reset(rst),
    .cpu(1'b0),              // 6502 mode
    .cpu_addr(cpu_addr),
    .cpu_data_out(cpu_data_out),
    .cpu_we(cpu_we),
    .cpu_pc(cpu_pc),
    .cpu_irq_n(1'b1),        // No interrupts
    .cpu_nmi_n(1'b1),        // No NMIs
    // Memory interfaces
    .ram_data_in(ram_out),
    .ram_data_out(ram_dout),
    .ram_addr(ram_addr),
    .ram_we(ram_we),
    // ROM interfaces
    .monitor_rom_addr(monitor_rom_addr),
    .monitor_rom_data(monitor_rom_data),
    .basic_rom_addr(basic_rom_addr),
    .basic_rom_data(basic_rom_data),
    // Font ROM interface
    .font_rom_data(font_rom_data)
);

assign led = cpu_pc[15:13];  // Show PC bits on LEDs

//
// 4. Video Memory System
//
wire screen_cs = (cpu_addr >= 16'h0400 && cpu_addr < 16'h0800); // $0400-$07FF

// Dual-port video RAM
wire [17:0] video_addr;
//wire [7:0] video_data;
wire video_en;

disk_image video_ram (
    // Port A: CPU access
    .clka(pix_clk),
    .ena(1'b1),
    .wea(cpu_we && screen_cs),
    .addra(cpu_addr[12:0]),
    .dina(cpu_data_out),
    .douta(),  // CPU reads from main RAM
    
    // Port B: Video access
    .clkb(pix_clk),
    .enb(video_en),
    .web(1'b0),
    .addrb(video_addr[12:0]),
    .dinb(8'h00),
    .doutb(video_data)
);

//
// 5. Video System
//
wire hs, vs, de;
wire signed [15:0] sx, sy;
wire [10:0] rom_debug_addr;
assign rom_debug_addr = (sy[8:4] * 40 + sx[9:4]);

// wire [7:0] char_code = video_data;
wire [7:0] char_code = switch ? basic_rom_data : video_data;

display_timings timings (
    .i_pix_clk(pix_clk),
    .i_rst(rst),
    .o_hs(hs),
    .o_vs(vs),
    .o_de(de),
    .o_sx(sx),
    .o_sy(sy)
);

// Apple II video memory mapping
//assign video_en = de && (sy < 480) && (sx < 640);
assign video_en = de && (sy < 384) && (sx < 640);

wire [5:0] column = (sx[8:3] > 6'd39) ? 6'd39 : sx[8:3];
assign video_addr = 1024 + ((sy[2:0] << 7) + (sy[8:6] * 40)) + column;

// Character generation using Font ROM
wire [5:0] char_line = sy[3:0]; // Which line of the character (0-15)
//wire [7:0] char_code = video_data;
//assign font_rom_addr = {char_code[6:0], char_line[3:0]}; // 128 chars * 16 lines
assign font_rom_addr = {char_code[6:0], char_line[3:0]}; // 128 chars * 16 lines

// Video output generation
reg [7:0] vga_r, vga_g, vga_b;

always @(posedge pix_clk) begin
    if (de && (sy < 480) && (sx < 640)) begin
        if (font_rom_data[7 - sx[2:0]]) begin // Use font ROM for pixel data
            {vga_r, vga_g, vga_b} = {8'hFF, 8'hFF, 8'hFF}; // White
        end else begin
            {vga_r, vga_g, vga_b} = {8'h30, 8'hB0, 8'h30}; // Green
        end
    end else begin
        {vga_r, vga_g, vga_b} = {8'h00, 8'h00, 8'h00}; // Blanking
    end

end


//----------------------------------------------------------
// Reset 
//----------------------------------------------------------
reg [15:0] reset_cnt;
reg cpu_reset;

always @(posedge pix_clk) begin
    if (rst) begin
        reset_cnt <= 0;
        cpu_reset <= 1;
    end else if (reset_cnt < 16'hFFFF) begin
        reset_cnt <= reset_cnt + 1;
    end else begin
        cpu_reset <= 0;
    end
end

//
// 6. HDMI Output
//
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

// HDMI differential outputs
OBUFDS #(.IOSTANDARD("TMDS_33")) tmds_buf_ch0 (.I(tmds_ch0_serial), .O(hdmi_data_p[0]), .OB(hdmi_data_n[0]));
OBUFDS #(.IOSTANDARD("TMDS_33")) tmds_buf_ch1 (.I(tmds_ch1_serial), .O(hdmi_data_p[1]), .OB(hdmi_data_n[1]));
OBUFDS #(.IOSTANDARD("TMDS_33")) tmds_buf_ch2 (.I(tmds_ch2_serial), .O(hdmi_data_p[2]), .OB(hdmi_data_n[2]));
OBUFDS #(.IOSTANDARD("TMDS_33")) tmds_buf_chc (.I(tmds_chc_serial), .O(hdmi_clk_p), .OB(hdmi_clk_n));

endmodule

