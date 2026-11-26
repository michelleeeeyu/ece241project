`timescale 1ns / 1ps

// ============================================================================
//  testbench.v  --  ModelSim testbench for square_test
//
//  What it does:
//    1. Fills the (stand-in) screen with old pixels, then resets with KEY[0]
//       and checks that the whole screen is cleared to CLEAR_COLOR.
//    2. Presses KEY[3] (go) to draw the 32x32 template and checks:
//         - template pixels read by the FSM     (expect 32*32 = 1024)
//         - pixels drawn                        (expect the non-transparent
//                                                pixels of the template)
//         - BCD counter digits d4..d0 and HEX4..HEX0 show that count
//         - every drawn pixel lies inside the template area centred at
//           (320,240) and has the template's color for that position
//           (i.e. address, color and write are lined up)
//    3. Resets again and checks the template is erased and the count is 0.
//
//  The real vga_adapter and object_mem use Altera megafunctions (altsyncram/
//  altpll). By default this file provides lightweight behavioural stand-ins
//  so you don't need the altera_mf library; the stand-in object_mem holds a
//  test pattern instead of the MIF. To simulate with the real modules
//  instead, compile with +define+USE_REAL_VGA, add object_mem.v and the
//  vga_adapter files, and add the altera_mf library (vsim -L altera_mf_ver).
// ============================================================================

module testbench;

    reg         CLOCK_50;
    reg  [3:0]  KEY;
    wire [6:0]  HEX4, HEX3, HEX2, HEX1, HEX0;
    wire [7:0]  VGA_R, VGA_G, VGA_B;
    wire        VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK;

    // ---------------- DUT ----------------
    square_test DUT (
        .CLOCK_50(CLOCK_50), .KEY(KEY),
        .HEX4(HEX4), .HEX3(HEX3), .HEX2(HEX2), .HEX1(HEX1), .HEX0(HEX0),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N), .VGA_CLK(VGA_CLK)
    );

    // ---------------- 50 MHz clock ----------------
    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    // ---------------- expected values ----------------
    localparam COLS        = 640;
    localparam ROWS        = 480;
    localparam SIZE        = 32;
    localparam XC_CENTER   = 320;
    localparam YC_CENTER   = 240;
    localparam X0          = XC_CENTER - SIZE/2;   // top-left corner of template
    localparam Y0          = YC_CENTER - SIZE/2;
    localparam EXP_READS   = SIZE * SIZE;      // 1024
    localparam ST_A = 3'b010, ST_D = 3'b101;   // FSM states (idle, done drawing)
    integer    exp_drawn;                      // non-transparent template pixels
    integer    k;

    initial begin
        exp_drawn = 0;
        for (k = 0; k < SIZE*SIZE; k = k + 1)
            if (DUT.OM.mem[k] !== DUT.TRANSPARENT) exp_drawn = exp_drawn + 1;
    end

    // ---------------- monitors ----------------
    integer read_count    = 0;
    integer drawn_count   = 0;
    integer clear_count   = 0;
    integer bad_xy        = 0;
    integer bad_color     = 0;
    integer errors        = 0;

    // pixels as the DUT drives them into the VGA adapter
    wire [9:0] vga_x = DUT.VGA.x;
    wire [8:0] vga_y = DUT.VGA.y;
    wire [8:0] vga_c = DUT.VGA.color;

    always @(posedge CLOCK_50) begin
        if (KEY[0] && DUT.write && !DUT.clearing) read_count = read_count + 1;

        if (KEY[0] && DUT.VGA.write && DUT.VGA_clearing) begin
            clear_count = clear_count + 1;
            if (vga_c !== DUT.CLEAR_COLOR) bad_color = bad_color + 1;
        end

        if (KEY[0] && DUT.VGA.write && !DUT.VGA_clearing) begin
            drawn_count = drawn_count + 1;

            if ((^vga_x === 1'bx) || (^vga_y === 1'bx)) begin
                if (bad_xy < 5)
                    $display("[%0t] ERROR: unknown VGA coordinate x=%b y=%b", $time, vga_x, vga_y);
                bad_xy = bad_xy + 1;
            end
            else if (vga_x < X0 || vga_x >= X0 + SIZE || vga_y < Y0 || vga_y >= Y0 + SIZE) begin
                if (bad_xy < 5)
                    $display("[%0t] ERROR: pixel (%0d,%0d) outside template area", $time, vga_x, vga_y);
                bad_xy = bad_xy + 1;
            end
            else if (vga_c !== DUT.OM.mem[(vga_y - Y0) * SIZE + (vga_x - X0)]) begin
                if (bad_color < 5)
                    $display("[%0t] ERROR: pixel (%0d,%0d) color %h, template has %h", $time,
                             vga_x, vga_y, vga_c, DUT.OM.mem[(vga_y - Y0) * SIZE + (vga_x - X0)]);
                bad_color = bad_color + 1;
            end
        end
    end

    // number of screen pixels that are not CLEAR_COLOR
    function integer dirty_pixels;
        input dummy;
        integer i;
        begin
            dirty_pixels = 0;
            for (i = 0; i < COLS*ROWS; i = i + 1)
                if (DUT.VGA.fb[i] !== DUT.CLEAR_COLOR) dirty_pixels = dirty_pixels + 1;
        end
    endfunction

    task do_reset;
        begin
            @(negedge CLOCK_50) KEY[0] = 1'b0;
            repeat (5) @(posedge CLOCK_50);
            @(negedge CLOCK_50) KEY[0] = 1'b1;
            wait (DUT.y_Q == ST_A);           // screen clear finished
            repeat (5) @(posedge CLOCK_50);
        end
    endtask

    // ---------------- 7-segment decode for checking ----------------
    function [6:0] seg;
        input [3:0] h;
        case (h)
            4'h0: seg = 7'b1000000; 4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100; 4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001; 4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010; 4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000; 4'h9: seg = 7'b0011000;
            default: seg = 7'b1111111;
        endcase
    endfunction

    task check;
        input [255:0] name;
        input integer got, exp;
        begin
            if (got !== exp) begin
                $display("  FAIL  %0s : got %0d, expected %0d", name, got, exp);
                errors = errors + 1;
            end else
                $display("  PASS  %0s : %0d", name, got);
        end
    endtask

    // ---------------- stimulus ----------------
    initial begin
        KEY = 4'b1111;              // all keys released (active-low)

        // pretend an old picture is on the screen (e.g. an object drawn before reset)
        for (k = 0; k < COLS*ROWS; k = k + 1) DUT.VGA.fb[k] = 9'h1FF;

        // ---- reset: whole screen must be cleared ----
        $display("[%0t] Pressing KEY[0] (reset)", $time);
        do_reset;
        $display("\n=========== RESET 1 ===========");
        check("screen pixels cleared",         clear_count,      COLS*ROWS);
        check("pixels left uncleared",         dirty_pixels(0),  0);
        check("pixel count after reset",
              DUT.d4*10000 + DUT.d3*1000 + DUT.d2*100 + DUT.d1*10 + DUT.d0, 0);

        // ---- draw the template ----
        $display("[%0t] Pressing KEY[3] to draw template", $time);
        @(negedge CLOCK_50) KEY[3] = 1'b0;
        repeat (3) @(posedge CLOCK_50);
        @(negedge CLOCK_50) KEY[3] = 1'b1;
        wait (DUT.y_Q == ST_D);
        wait (DUT.y_Q == ST_A);
        repeat (5) @(posedge CLOCK_50);
        $display("[%0t] Drawing finished", $time);

        $display("\n=========== DRAW ===========");
        check("template pixels read",          read_count,    EXP_READS);
        check("pixels drawn",                  drawn_count,   exp_drawn);
        check("BCD value d4..d0",
              DUT.d4*10000 + DUT.d3*1000 + DUT.d2*100 + DUT.d1*10 + DUT.d0,
              exp_drawn);
        check("HEX4 segments ok", HEX4 === seg(exp_drawn / 10000 % 10), 1);
        check("HEX3 segments ok", HEX3 === seg(exp_drawn / 1000 % 10), 1);
        check("HEX2 segments ok", HEX2 === seg(exp_drawn / 100 % 10), 1);
        check("HEX1 segments ok", HEX1 === seg(exp_drawn / 10 % 10), 1);
        check("HEX0 segments ok", HEX0 === seg(exp_drawn % 10), 1);
        check("bad/unknown VGA coordinates",   bad_xy,        0);
        check("pixels with wrong color",       bad_color,     0);
        check("template pixels on screen",     dirty_pixels(0), exp_drawn);

        // ---- reset again: template must be erased ----
        $display("[%0t] Pressing KEY[0] (reset)", $time);
        clear_count = 0;
        do_reset;
        $display("\n=========== RESET 2 ===========");
        check("screen pixels cleared",         clear_count,      COLS*ROWS);
        check("pixels left uncleared",         dirty_pixels(0),  0);
        check("pixel count after reset",
              DUT.d4*10000 + DUT.d3*1000 + DUT.d2*100 + DUT.d1*10 + DUT.d0, 0);
        check("adapter resetn held high",      DUT.VGA.resetn,   1);

        if (errors == 0) $display("\n*** ALL TESTS PASSED ***\n");
        else             $display("\n*** %0d TEST(S) FAILED ***\n", errors);
        $stop;
    end

    // ---------------- watchdog ----------------
    initial begin
        #50_000_000;   // 50 ms
        $display("TIMEOUT: FSM never finished (y_Q=%b)", DUT.y_Q);
        $stop;
    end

endmodule


`ifndef USE_REAL_VGA
// ============================================================================
//  Behavioural stand-in for vga_adapter (simulation only).
//  Same ports as the DE1-SoC vga_adapter; records writes into a frame buffer.
// ============================================================================
module vga_adapter (resetn, clock, color, x, y, write,
                    VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS,
                    VGA_BLANK_N, VGA_SYNC_N, VGA_CLK);
    parameter RESOLUTION = "640x480";
    parameter COLOR_DEPTH = 9;

    input        resetn, clock, write;
    input  [8:0] color;
    input  [9:0] x;
    input  [8:0] y;
    output [7:0] VGA_R, VGA_G, VGA_B;
    output       VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK;

    reg [8:0] fb [0:640*480-1];

    always @(posedge clock)
        if (write && x < 640 && y < 480)
            fb[y*640 + x] <= color;

    assign VGA_R = 8'd0;  assign VGA_G = 8'd0;  assign VGA_B = 8'd0;
    assign VGA_HS = 1'b1; assign VGA_VS = 1'b1;
    assign VGA_BLANK_N = 1'b1; assign VGA_SYNC_N = 1'b0;
    assign VGA_CLK = clock;
endmodule

// ============================================================================
//  Behavioural stand-in for object_mem (simulation only).
//  Same ports and 1-clock read latency as the altsyncram ROM in object_mem.v.
//  Instead of the MIF it holds a test pattern in which every 5th pixel is
//  transparent (0) and the others have a color that depends on the address.
// ============================================================================
module object_mem (address, clock, q);
    parameter n = 9;
    parameter Mn = 10;
    parameter INIT_FILE = "";

    input  wire [Mn-1:0] address;
    input  wire clock;
    output reg  [n-1:0] q;

    reg [n-1:0] mem [0:(1<<Mn)-1];
    integer i;
    initial
        for (i = 0; i < (1<<Mn); i = i + 1)
            mem[i] = (i % 5 == 0) ? {n{1'b0}} : ((i * 37) % ((1<<n) - 1)) + 1;

    always @(posedge clock)
        q <= mem[address];
endmodule
`endif
