`timescale 1ns/1ps
/*
 * Self-checking testbench for the game FSM in square_test (ModelSim).
 *
 * It watches what square_test sends to the VGA adapter (dut.pixel_write / VGA_x / VGA_y /
 * pixel_color) and the game state (dut.g_Q), and drives the switches and keys like a player.
 * Only LEDR[8] (PASS) and LEDR[9] (FAIL) exist in this design, so the game state is read from dut.g_Q.
 *
 * Checks
 *   - reset -> repaint -> S_ORDER
 *   - KEY[3] with no shape switch up does nothing; KEY[2] in S_ORDER does nothing
 *   - KEY[3] places the order and starts drawing
 *   - drawn pixels stay inside the box, come from the selected ROM, and match the HEX counter
 *   - KEY[3] in S_SUBMIT does nothing; KEY[2] submits
 *   - placeholder grading: SW[9] up -> PASS (LEDR[8]), down -> FAIL (LEDR[9]),
 *     and both LEDs are off outside S_RESULT even though the old grade is remembered
 *   - KEY[2] and KEY[3] in S_RESULT do nothing; KEY[1] repaints the screen and returns to S_ORDER
 *   - SW[1]+SW[2] both up -> shape 2 is drawn (priority)
 *   - HOLDING a key down never runs the game through two steps (KEY[3], KEY[2], KEY[1] each held)
 *   - KEY[0] resets from the middle of the game
 *
 * Run it from the folder that contains the ./MIF folder, otherwise the ROMs load empty.
 */
module testbench;

    // ------------------------------------------------------------------ DUT hookup
    reg         CLOCK_50 = 1'b0;
    reg  [3:0]  KEY      = 4'b1111;      // active-low (1 = not pressed)
    reg  [9:0]  SW       = 10'b0;
    wire [9:0]  LEDR;
    wire [6:0]  HEX4, HEX3, HEX2, HEX1, HEX0;
    wire [7:0]  VGA_R, VGA_G, VGA_B;
    wire        VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK;

    square_test dut (
        .CLOCK_50(CLOCK_50), .SW(SW), .KEY(KEY), .LEDR(LEDR),
        .HEX4(HEX4), .HEX3(HEX3), .HEX2(HEX2), .HEX1(HEX1), .HEX0(HEX0),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N), .VGA_CLK(VGA_CLK));

    always #10 CLOCK_50 = ~CLOCK_50;     // 50 MHz

    // ------------------------------------------------------------------ constants
    localparam S_CLEAR = 0, S_ORDER = 1, S_DRAW = 2, S_SUBMIT = 3, S_RESULT = 4;
    localparam NPIX = 76800;
    localparam BOX_X0 = 128, BOX_X1 = 191, BOX_Y0 = 88, BOX_Y1 = 151;

    // ------------------------------------------------------------------ write monitor
    integer n_repaint, n_draw, n_outside, n_wrong_rom;
    integer ordered_id;                  // which ROM the test expects to be drawn (1..3)
    integer errors;
    reg     done = 1'b0;
    reg [8:0] exp_color;

    always @(posedge CLOCK_50) begin
        if (dut.pixel_write === 1'b1) begin
            if (dut.VGA_clear === 1'b1) begin
                n_repaint = n_repaint + 1;
            end else begin
                n_draw = n_draw + 1;
                if (dut.VGA_x < BOX_X0 || dut.VGA_x > BOX_X1 ||
                    dut.VGA_y < BOX_Y0 || dut.VGA_y > BOX_Y1) n_outside = n_outside + 1;
                exp_color = (ordered_id == 1) ? dut.color1 :
                            (ordered_id == 2) ? dut.color2 : dut.color3;
                if (dut.pixel_color !== exp_color) n_wrong_rom = n_wrong_rom + 1;
            end
        end
    end

    // ------------------------------------------------------------------ helpers
    task check(input cond, input [8*80-1:0] msg);
    begin
        if (cond) $display("  ok:   %0s", msg);
        else begin
            errors = errors + 1;
            $display("  FAIL: %0s", msg);
        end
    end
    endtask

    task zero_counters;
    begin
        n_repaint = 0; n_draw = 0; n_outside = 0; n_wrong_rom = 0;
    end
    endtask

    task wait_cycles(input integer n);
    begin
        repeat (n) @(negedge CLOCK_50);
    end
    endtask

    // press and release a key (k = 0..3), with a few idle cycles after
    task tap(input integer k);
    begin
        @(negedge CLOCK_50); KEY[k] = 1'b0;
        wait_cycles(3);
        KEY[k] = 1'b1;
        wait_cycles(3);
    end
    endtask

    task wait_state(input integer s, input integer max_cycles);
        integer t;
    begin
        t = 0;
        while (dut.g_Q !== s && t < max_cycles) begin
            @(negedge CLOCK_50); t = t + 1;
        end
        if (dut.g_Q !== s) begin
            errors = errors + 1;
            $display("  FAIL: never reached state %0d (stuck in %0d)", s, dut.g_Q);
        end
        wait_cycles(5);
    end
    endtask

    task do_reset;
    begin
        @(negedge CLOCK_50); KEY[0] = 1'b0;
        wait_cycles(5);
        KEY[0] = 1'b1;
        wait_state(S_ORDER, 200000);
    end
    endtask

    // set switches, tap KEY[3] to place the order, wait for the submit state
    task order_and_draw(input [2:0] sw, input integer id);
    begin
        SW[2:0] = sw;
        ordered_id = id;
        zero_counters;
        tap(3);
        check(dut.g_Q === S_DRAW, "order placed: game is drawing");
        wait_state(S_SUBMIT, 50000);
        check(n_draw > 0,          "something was drawn (if not: check the MIF paths)");
        check(n_outside == 0,      "all shape pixels are inside the 64x64 box");
        check(n_wrong_rom == 0,    "every pixel came from the ordered shape's ROM");
        check(dut.d4*10000 + dut.d3*1000 + dut.d2*100 + dut.d1*10 + dut.d0 == n_draw,
                                   "HEX counter equals number of pixels drawn");
    end
    endtask

    // ------------------------------------------------------------------ test sequence
    integer draw_before;

    initial begin
        errors = 0; ordered_id = 1;
        zero_counters;
        $display("=== game FSM testbench ===");
        wait_cycles(3);

        // ---- 1. reset ------------------------------------------------------------
        $display("[1] reset -> repaint -> ORDER");
        do_reset;
        check(n_repaint == NPIX, "repaint wrote exactly 76800 pixels");
        check(n_draw == 0,       "no shape pixels during the repaint");
        check(dut.g_Q === S_ORDER, "game is in S_ORDER");
        check(LEDR[9:8] === 2'b00, "PASS/FAIL LEDs are off after reset");

        // ---- 2. ignored keys while ordering ----------------------------------------
        $display("[2] keys that should be ignored while ordering");
        SW[2:0] = 3'b000;
        tap(3);
        check(dut.g_Q === S_ORDER, "KEY[3] with no shape selected does nothing");
        SW[2:0] = 3'b010;
        tap(2);
        check(dut.g_Q === S_ORDER, "KEY[2] while ordering does nothing");

        // ---- 3. round A: order shape 2, PASS ---------------------------------------
        $display("[3] round A: order shape2, then submit with SW[9] up (PASS)");
        order_and_draw(3'b010, 2);
        check(dut.g_Q === S_SUBMIT, "game is waiting in S_SUBMIT");
        check(LEDR[9:8] === 2'b00, "PASS/FAIL LEDs are off before submitting");
        draw_before = n_draw;
        tap(3);
        check(dut.g_Q === S_SUBMIT, "KEY[3] in S_SUBMIT does nothing");
        check(n_draw == draw_before, "nothing more was drawn");
        SW[9] = 1'b1;
        tap(2);
        check(dut.g_Q === S_RESULT, "KEY[2] submits -> S_RESULT");
        check(LEDR[8] === 1'b1 && LEDR[9] === 1'b0, "result is PASS (LEDR[8] on, LEDR[9] off)");
        tap(2);
        check(dut.g_Q === S_RESULT, "KEY[2] in S_RESULT does nothing");
        tap(3);
        check(dut.g_Q === S_RESULT, "KEY[3] in S_RESULT does nothing");

        // ---- 4. next order -> repaint ------------------------------------------------
        $display("[4] KEY[1] in RESULT repaints and goes back to ORDER");
        zero_counters;
        tap(1);
        check(dut.g_Q === S_CLEAR, "game went to S_CLEAR");
        wait_state(S_ORDER, 200000);
        check(n_repaint == NPIX, "repaint wrote exactly 76800 pixels");
        check(n_draw == 0,       "no shape pixels during the repaint");
        check(dut.grade === 1'b1, "the old grade (PASS) is still remembered");
        check(LEDR[9:8] === 2'b00, "but the LEDs are off outside S_RESULT");

        // ---- 5. round B: shape 3, FAIL ---------------------------------------------
        $display("[5] round B: order shape3, then submit with SW[9] down (FAIL)");
        SW[9] = 1'b0;
        order_and_draw(3'b100, 3);
        SW[9] = 1'b0;
        tap(2);
        check(dut.g_Q === S_RESULT, "KEY[2] submits -> S_RESULT");
        check(LEDR[9] === 1'b1 && LEDR[8] === 1'b0, "result is FAIL (LEDR[9] on, LEDR[8] off)");
        zero_counters;
        tap(1);
        wait_state(S_ORDER, 200000);
        check(n_repaint == NPIX, "repaint wrote exactly 76800 pixels");

        // ---- 6. priority -------------------------------------------------------------
        $display("[6] SW[1]+SW[2] both up: shape2 is drawn");
        order_and_draw(3'b110, 2);
        check(n_wrong_rom == 0, "shape2 was drawn (SW[1] beats SW[2])");
        tap(2);                                    // submit (SW[9] is down -> FAIL)
        zero_counters;
        tap(1);                                    // next order
        wait_state(S_ORDER, 200000);
        check(n_repaint == NPIX, "repaint wrote exactly 76800 pixels");

        // ---- 7. holding keys down ----------------------------------------------------
        $display("[7] holding each key down must not run through two steps");
        SW[2:0] = 3'b001;
        ordered_id = 1;
        zero_counters;
        KEY[3] = 1'b0;                             // hold KEY[3] through the whole drawing
        wait_state(S_SUBMIT, 50000);
        wait_cycles(3000);
        check(dut.g_Q === S_SUBMIT, "KEY[3] held: game waits in S_SUBMIT");
        check(n_draw > 0 && n_draw <= 4096, "KEY[3] held: the shape was drawn only once");
        check(dut.d4*10000 + dut.d3*1000 + dut.d2*100 + dut.d1*10 + dut.d0 == n_draw,
                                    "HEX counter equals number of pixels drawn");
        KEY[3] = 1'b1;
        wait_cycles(5);
        KEY[2] = 1'b0;                             // hold KEY[2] (submit)
        wait_cycles(3000);
        check(dut.g_Q === S_RESULT, "KEY[2] held: game waits in S_RESULT");
        KEY[2] = 1'b1;
        wait_cycles(5);
        zero_counters;
        KEY[1] = 1'b0;                             // hold KEY[1] longer than the whole repaint
        wait_cycles(100000);
        check(dut.g_Q === S_ORDER, "KEY[1] held: repaint finished and game waits in S_ORDER");
        check(n_repaint == NPIX,   "KEY[1] held: repaint ran exactly once (76800 pixels)");
        check(n_draw == 0,         "KEY[1] held: nothing was drawn");
        KEY[1] = 1'b1;
        wait_cycles(5);

        // ---- 7. reset from the middle of the game -----------------------------------
        $display("[8] KEY[0] resets from S_SUBMIT");
        order_and_draw(3'b001, 1);
        SW[2:0] = 3'b000;
        zero_counters;
        do_reset;
        check(dut.g_Q === S_ORDER, "back in S_ORDER after reset");
        check(n_repaint == NPIX,   "reset repainted the screen");
        check(LEDR[8] === 1'b0 && LEDR[9] === 1'b0, "result was cleared");

        // ---- summary ---------------------------------------------------------------
        $display("=============================");
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d CHECK(S) FAILED", errors);
        done = 1'b1;
        $stop;
    end

    // safety net in case something hangs
    initial begin
        #400_000_000;
        if (!done) begin
            $display("TIMEOUT - simulation took too long");
            $stop;
        end
    end

endmodule
