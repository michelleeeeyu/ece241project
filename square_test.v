/*
 *  This code illustrates usage of the VGA output in the DE1-SoC board. The code uses a VGA
 *  adapter to send pixel colors to the VGA display.
 *
 *  KEY[0] (reset): clears the whole screen to CLEAR_COLOR and clears the pixel count. The
 *                  clear runs once KEY[0] is released and takes about 6 ms.
 *  KEY[3] (draw):  draws the template image, which is read pixel by pixel from a small
 *                  memory (object_mem, loaded from a MIF file), centered at
 *                  (X_OFFSET, Y_OFFSET).
 *
 *  Pixels of the template whose color is TRANSPARENT are skipped. Every pixel that is
 *  actually drawn is counted, and the count is shown as a decimal number on HEX4-0.
 *
*/
module square_test(CLOCK_50, KEY, HEX4, HEX3, HEX2, HEX1, HEX0, VGA_R, VGA_G, VGA_B,
                VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK);
    
    // specify the number of bits needed for an X (column) pixel coordinate on the VGA display
    parameter nX = 10;
    // specify the number of bits needed for a Y (row) pixel coordinate on the VGA display
    parameter nY = 9;
    // screen size (must match the vga_adapter's RESOLUTION, 640x480 by default)
    parameter COLS = 640, ROWS = 480;

    // state codes for the FSM
    parameter CLR = 3'b000,     // clearing a row of the screen
              CLR_NEXT = 3'b001,// go to next row of the screen
              A = 3'b010,       // idle, wait for KEY[3]
              B = 3'b011,       // drawing a row of the template
              C = 3'b100,       // go to next row of the template
              D = 3'b101;       // done drawing

    // template size is 2^xOBJ x 2^yOBJ pixels (must be powers of 2, and must match the MIF)
    parameter xOBJ = 5, yOBJ = 5;
    parameter SIZE_X = 1 << xOBJ;
    parameter SIZE_Y = 1 << yOBJ;
    parameter TEMPLATE_FILE = "./MIF/template_32x32_9.mif";

    // template pixels of this color are not drawn (and not counted)
    parameter TRANSPARENT = 9'b000_000_000;
    // color used to clear the screen on reset
    parameter CLEAR_COLOR = 9'b000_000_000;
	
    input CLOCK_50;    
    input [3:0] KEY;
    output [6:0] HEX4, HEX3, HEX2, HEX1, HEX0;
    output [7:0] VGA_R;
    output [7:0] VGA_G;
    output [7:0] VGA_B;
    output VGA_HS;
    output VGA_VS;
    output VGA_BLANK_N;
    output VGA_SYNC_N;
    output VGA_CLK;    
    
    wire [8:0] obj_color;           // template pixel color, read from memory
    wire [nX-1:0] X;                // used to record the center of the template
    wire [nY-1:0] Y;                // used to record the center of the template
    wire [nX-1:0] XC;               // column counter (screen when clearing, template when drawing)
    wire [nY-1:0] YC;               // row counter
    wire go;                        // used by FSM
    reg write, clearing;            // write a pixel; the pixel is a screen-clear pixel
    reg Lxc, Lyc, Exc, Eyc;         // counter control signals
    reg [2:0] y_Q, Y_D;             // FSM
    wire [nX-1:0] VGA_x;            // (x,y), write and clearing, delayed by one clock cycle
    wire [nY-1:0] VGA_y;            // to line up with the pixel color coming out of the memory
    wire VGA_write, VGA_clearing;
    wire [8:0] VGA_color;
    wire pixel_write;               // a pixel is written to the screen
    wire pixel_count;               // a template pixel is drawn (counted)
    
    // use offsets to center the template on the VGA display
    parameter X_OFFSET = 320;
    parameter Y_OFFSET = 240;
    assign X = X_OFFSET;
    assign Y = Y_OFFSET;

    // these counters generate pixel coordinates, for the whole screen when clearing it, and
    // for the template when drawing it
    Up_count U1 ({nX{1'd0}}, CLOCK_50, KEY[0], Lxc, Exc, XC);
        defparam U1.n = nX;
    Up_count U2 ({nY{1'd0}}, CLOCK_50, KEY[0], Lyc, Eyc, YC);
        defparam U2.n = nY;

    assign go = ~KEY[3];

    // FSM state table
    always @ (*)
        case (y_Q)
            CLR:      if (XC != COLS-1) Y_D = CLR;      // clear a row of the screen
                      else Y_D = CLR_NEXT;
            CLR_NEXT: if (YC != ROWS-1) Y_D = CLR;      // next row of the screen
                      else Y_D = A;                     // screen is clear
            A:  if (!go) Y_D = A;
                else Y_D = B;
            B:  if (XC != SIZE_X-1) Y_D = B;    // template x coordinate (column)
                else Y_D = C;
            C:  if (YC != SIZE_Y-1) Y_D = B;    // template y coordinate (row)
                else Y_D = D;
            D:  if (go) Y_D = D;                // wait for KEY[3] to be released
                else Y_D = A;
            default: Y_D = A;
        endcase
    // FSM outputs
    always @ (*)
    begin
        // default assignments
        write = 1'b0; clearing = 1'b0; Lxc = 1'b0; Lyc = 1'b0; Exc = 1'b0; Eyc = 1'b0;
        case (y_Q)
            CLR:      begin Exc = 1'b1; write = 1'b1; clearing = 1'b1; end
            CLR_NEXT: begin Lxc = 1'b1; Eyc = 1'b1; end
            A:  begin Lxc = 1'b1; Lyc = 1'b1; end   // load (XC,YC) counter
            B:  begin Exc = 1'b1; write = 1'b1; end // enable XC, read/write pixel
            C:  begin Lxc = 1'b1; Eyc = 1'b1; end   // enable YC, load XC
            D:  Lyc = 1'b1;                         // load YC
        endcase
    end

    // reset starts the FSM in the screen-clear state
    always @(posedge CLOCK_50)
        if (!KEY[0])
            y_Q <= CLR;
        else
            y_Q <= Y_D;

    // template memory. The address is {row, column}, which works because the template width
    // is a power of 2. The pixel color appears on obj_color one clock cycle later
    object_mem OM ({YC[yOBJ-1:0], XC[xOBJ-1:0]}, CLOCK_50, obj_color);
        defparam OM.n = 9;
        defparam OM.Mn = xOBJ + yOBJ;
        defparam OM.INIT_FILE = TEMPLATE_FILE;

    // compute the screen location of the current pixel and register it, together with write
    // and clearing, so that they stay synchronized with the memory's output. When clearing,
    // (XC,YC) is the screen location; when drawing, the template is centered at (X,Y)
    wire [nX-1:0] half_x = SIZE_X >> 1;
    wire [nY-1:0] half_y = SIZE_Y >> 1;
    regn RX (clearing ? XC : X - half_x + XC, KEY[0], 1'b1, CLOCK_50, VGA_x);
        defparam RX.n = nX;
    regn RY (clearing ? YC : Y - half_y + YC, KEY[0], 1'b1, CLOCK_50, VGA_y);
        defparam RY.n = nY;
    regn RW ({write, clearing}, KEY[0], 1'b1, CLOCK_50, {VGA_write, VGA_clearing});
        defparam RW.n = 2;

    // clear pixels are always written; template pixels only if they are not transparent,
    // and only those are counted
    assign VGA_color = VGA_clearing ? CLEAR_COLOR : obj_color;
    assign pixel_count = VGA_write & !VGA_clearing & (obj_color != TRANSPARENT);
    assign pixel_write = (VGA_write & VGA_clearing) | pixel_count;
	
	wire clear_count = (y_Q == A) & go;
	wire[3:0] d4, d3, d2, d1, d0;
	
	bcd_count5 UP (CLOCK_50, KEY[0], clear_count, pixel_count, d4, d3, d2, d1, d0);
	
	hex7seg H4 (d4, HEX4);
    hex7seg H3 (d3, HEX3);
    hex7seg H2 (d2, HEX2);
    hex7seg H1 (d1, HEX1);
    hex7seg H0 (d0, HEX0);

    // the adapter's resetn is held high so the VGA signal never stops; if it is reset, the
    // monitor loses sync, and the old picture comes back a few seconds later when it resyncs
    vga_adapter VGA (
        .resetn(1'b1),
        .clock(CLOCK_50),
        .color(VGA_color),
        .x(VGA_x),
        .y(VGA_y),
        .write(pixel_write),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS),
        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N),
        .VGA_CLK(VGA_CLK));

endmodule

module regn(R, Resetn, E, Clock, Q);
    parameter n = 8;
    input [n-1:0] R;
    input Resetn, E, Clock;
    output reg [n-1:0] Q;

    always @(posedge Clock)
        if (!Resetn)
            Q <= 0;
        else if (E)
            Q <= R;
endmodule

// n-bit up-counter with reset, load, and enable
module Up_count (R, Clock, Resetn, L, E, Q);
    parameter n = 8;
    input [n-1:0] R;
    input Clock, Resetn, E, L;
    output reg [n-1:0] Q;

    always @ (posedge Clock)
        if (Resetn == 0)
            Q <= {n{1'b0}};
        else if (L == 1)
            Q <= R;
        else if (E)
            Q <= Q + 1'b1;
endmodule

module bcd_count5 (Clock, Resetn, Clr, E, D4, D3, D2, D1, D0);
    input wire Clock, Resetn, Clr, E;
    output reg [3:0] D4, D3, D2, D1, D0;

    always @ (posedge Clock)
        if (!Resetn || Clr)
        begin
            D4 <= 4'b0;
            D3 <= 4'b0;
            D2 <= 4'b0;
            D1 <= 4'b0;
            D0 <= 4'b0;
        end
        else if (E)
        begin
            if (D0 != 4'd9) D0 <= D0 + 4'd1;
            else begin
                D0 <= 4'd0;
                if (D1 != 4'd9) D1 <= D1 + 4'd1;
                else begin
                    D1 <= 4'd0;
                    if (D2 != 4'd9) D2 <= D2 + 4'd1;
                    else begin
                        D2 <= 4'd0;
                        if (D3 != 4'd9) D3 <= D3 + 4'd1;
                        else begin
                            D3 <= 4'd0;
                            D4 <= D4 + 4'd1;
                        end
                    end
                end
            end
        end
endmodule

module hex7seg (hex, display);
    input [3:0] hex;
    output [6:0] display;

    reg [6:0] display;

    /*
     *       0  
     *      ---  
     *     |   |
     *    5|   |1
     *     | 6 |
     *      ---  
     *     |   |
     *    4|   |2
     *     |   |
     *      ---  
     *       3  
     */
    always @ (hex)
        case (hex)
            4'h0: display = 7'b1000000;
            4'h1: display = 7'b1111001;
            4'h2: display = 7'b0100100;
            4'h3: display = 7'b0110000;
            4'h4: display = 7'b0011001;
            4'h5: display = 7'b0010010;
            4'h6: display = 7'b0000010;
            4'h7: display = 7'b1111000;
            4'h8: display = 7'b0000000;
            4'h9: display = 7'b0011000;
            4'hA: display = 7'b0001000;
            4'hB: display = 7'b0000011;
            4'hC: display = 7'b1000110;
            4'hD: display = 7'b0100001;
            4'hE: display = 7'b0000110;
            4'hF: display = 7'b0001110;
        endcase
endmodule
