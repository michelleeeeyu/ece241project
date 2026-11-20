`timescale 1ns / 1ps

// ============================================================================
//  testbench.v  --  ModelSim testbench for square_test
//
//  What it does:
//    1. Holds KEY[0] low to reset, then releases it.
//    2. Presses KEY[3] (go) briefly to start drawing the 50x50 box.
//    3. Waits for the FSM to return to state A (drawing finished).
//    4. Checks:
//         - total pixels written by the FSM     (expect 50*50 = 2500)
//         - outline pixels counted (pixel_write) (expect 4*50-4 = 196)
//         - BCD counter digits d4..d0            (expect 0 0 1 9 6)
//         - HEX4..HEX0 segment patterns match those digits
//         - every x/y sent to the VGA adapter is a known value and lies
//           inside the box centred at (160,120)
//
//  The real vga_adapter uses Altera megafunctions (altsyncram/altpll).
//  By default this file provides a lightweight behavioural stand-in so
//  you don't need the altera_mf library. To simulate with the real
//  adapter instead, compile with +define+USE_REAL_VGA and add the
//  altera_mf library (vsim -L altera_mf_ver ...).
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
    localparam SIZE        = 50;
    localparam XC_CENTER   = 160;
    localparam YC_CENTER   = 120;
    localparam EXP_WRITES  = SIZE * SIZE;      // 2500
    localparam EXP_OUTLINE = 4 * SIZE - 4;     // 196

    // ---------------- monitors ----------------
    integer write_count   = 0;
    integer outline_count = 0;
    integer bad_xy        = 0;
    integer errors        = 0;

    // coordinates as the DUT drives them into the VGA adapter
    wire [9:0] vga_x = DUT.VGA.x;
    wire [8:0] vga_y = DUT.VGA.y;

    always @(posedge CLOCK_50) begin
        if (KEY[0] && DUT.write) begin
            write_count = write_count + 1;
            if (DUT.pixel_write) outline_count = outline_count + 1;

            if ((^vga_x === 1'bx) || (^vga_y === 1'bx)) begin
                if (bad_xy < 5)
                    $display("[%0t] ERROR: unknown VGA coordinate x=%b y=%b (XC=%0d YC=%0d)",
                             $time, vga_x, vga_y, DUT.XC, DUT.YC);
                bad_xy = bad_xy + 1;
            end
            else if (vga_x <  XC_CENTER - SIZE/2 || vga_x >= XC_CENTER + SIZE/2 ||
                     vga_y <  YC_CENTER - SIZE/2 || vga_y >= YC_CENTER + SIZE/2) begin
                if (bad_xy < 5)
                    $display("[%0t] ERROR: pixel (%0d,%0d) outside expected box", $time, vga_x, vga_y);
                bad_xy = bad_xy + 1;
            end
        end
    end

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

        // reset
        KEY[0] = 1'b0;
        repeat (5) @(posedge CLOCK_50);
        KEY[0] = 1'b1;
        repeat (5) @(posedge CLOCK_50);

        // press and release KEY[3] (go)
        $display("[%0t] Pressing KEY[3] to draw box", $time);
        @(negedge CLOCK_50) KEY[3] = 1'b0;
        repeat (3) @(posedge CLOCK_50);
        @(negedge CLOCK_50) KEY[3] = 1'b1;

        // wait for FSM to reach D, then return to A
        wait (DUT.y_Q == 2'b11);
        @(posedge CLOCK_50);
        wait (DUT.y_Q == 2'b00);
        repeat (5) @(posedge CLOCK_50);
        $display("[%0t] Drawing finished", $time);

        // ---------------- results ----------------
        $display("\n=========== RESULTS ===========");
        check("pixels written (write)",        write_count,   EXP_WRITES);
        check("outline pixels (pixel_write)",  outline_count, EXP_OUTLINE);
        check("BCD value d4..d0",
              DUT.d4*10000 + DUT.d3*1000 + DUT.d2*100 + DUT.d1*10 + DUT.d0,
              EXP_OUTLINE);
        check("HEX4 segments ok", HEX4 === seg(0), 1);
        check("HEX3 segments ok", HEX3 === seg(0), 1);
        check("HEX2 segments ok", HEX2 === seg(1), 1);
        check("HEX1 segments ok", HEX1 === seg(9), 1);
        check("HEX0 segments ok", HEX0 === seg(6), 1);
        check("bad/unknown VGA coordinates",   bad_xy,        0);

        if (errors == 0) $display("\n*** ALL TESTS PASSED ***\n");
        else             $display("\n*** %0d TEST(S) FAILED ***\n", errors);
        $stop;
    end

    // ---------------- watchdog ----------------
    initial begin
        #1_000_000;   // 1 ms
        $display("TIMEOUT: FSM never finished drawing (y_Q=%b)", DUT.y_Q);
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
    parameter RESOLUTION = "320x240";
    parameter COLOR_DEPTH = 9;

    input        resetn, clock, write;
    input  [8:0] color;
    input  [9:0] x;
    input  [8:0] y;
    output [7:0] VGA_R, VGA_G, VGA_B;
    output       VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK;

    reg [8:0] fb [0:320*240-1];

    always @(posedge clock)
        if (resetn && write && x < 320 && y < 240)
            fb[y*320 + x] <= color;

    assign VGA_R = 8'd0;  assign VGA_G = 8'd0;  assign VGA_B = 8'd0;
    assign VGA_HS = 1'b1; assign VGA_VS = 1'b1;
    assign VGA_BLANK_N = 1'b1; assign VGA_SYNC_N = 1'b0;
    assign VGA_CLK = clock;
endmodule
`endif
