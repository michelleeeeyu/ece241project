/*
 *  This code serves as an example that illustrates usage of the VGA output in the DE1-SoC 
 *  board. The code uses a VGA adapter to send pixel colors to the VGA display. To use the demo 
 *  first press KEY[0] to reset the circuit. It will display the contents of a video memory
 *  in the VGA adapter as a background image. Then, the user can choose to draw a colored box
 *  that is centered in the VGA display, by pressing KEY[3]. The box color is displayed on 
 *  LEDR[8:0], and the size of the box is displayed as a hexadecimal number on HEX1-0. You can
 *  set the color of the box by specifying any 9-bit color on switches SW[8:0] and then pressing
 *  KEY[1]. You can set the size of the box by specifying a new size on the SW switches and then
 *  pressing KEY[2]. Press KEY[3] to draw the box.
 *
*/
module square_test(CLOCK_50, SW, LEDR, KEY, HEX4, HEX3, HEX2, HEX1, HEX0, VGA_R, VGA_G, VGA_B,
                VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK);
    
    // specify the number of bits needed for an X (column) pixel coordinate on the VGA display
    parameter nX = 10;
    // specify the number of bits needed for a Y (row) pixel coordinate on the VGA display
    parameter nY = 9;

    // state codes for FSM that choses which object to draw at a given time
    parameter A = 2'b00, B = 2'b01, C = 2'b10, D = 2'b11;
	 
	 localparam RESOLUTION = "320x240"; 
	 defparam VGA.RESOLUTION = RESOLUTION;
	 defparam VGA.BACKGROUND_IMAGE = "./MIF/background2.mif";
	
    input CLOCK_50;    
    input [3:0] KEY;
	 input [9:0] SW;
    output [6:0] HEX4, HEX3, HEX2, HEX1, HEX0;
	 output [9:0] LEDR;
    output [7:0] VGA_R;
    output [7:0] VGA_G;
    output [7:0] VGA_B;
    output VGA_HS;
    output VGA_VS;
    output VGA_BLANK_N;
    output VGA_SYNC_N;
    output VGA_CLK;    
    
    wire [8:0] color;
    wire [nX-1:0] X;    // used to record the center of the box
    wire [nY-1:0] Y;    // used to record the center of the box
    wire [nY-1:0] size;
    wire [nX-1:0] XC;           // box offsets and counters
    wire [nY-1:0] YC;
    wire go;                        // used by FSM
    reg write, Lxc, Lyc, Exc, Eyc;  // box control signals
    reg [1:0] y_Q, Y_D;             // FSM
	 
    // use offsets to center the box on the VGA display
    parameter X_OFFSET = 160;
    parameter Y_OFFSET = 120;
    assign X = X_OFFSET;
    assign Y = Y_OFFSET;

	 assign size = 9'd64;
	 
	 
	 //game fsm logic
	 reg clearing;
	 
	 wire picked = (SW[2:0] != 3'b000); // a shape is picked
	 reg grade;
	 wire grade_pass_temp = SW[9]; // to be changed for actual grading
	 localparam clear = 3'b000, order = 3'b001, draw = 3'b010, submit = 3'b011, result = 3'b100;
	 reg [2:0] g_Q, g_D; // Q: current D: next state
	 always @ (*)
	 begin
		g_D = g_Q;
		case(g_Q)
			clear: if(!clearing)
						g_D = order;
			order: if(picked && ~KEY[3])
						g_D = draw;
			draw: if(y_Q == D) // D state from drawing fsm -> finished drawing 
						g_D = submit;
			submit: if(~KEY[2])
						g_D = result;
			result: if(~KEY[1])
						g_D = clear;
			default: g_D = clear;
		endcase
	 end
	
	
	 always @ (posedge CLOCK_50)
		if(!KEY[0])
		begin
			g_Q <= clear;
			grade <= 1'b0;
		end
		else
		begin
			g_Q <= g_D;
			if(g_Q == submit && ~KEY[2])
				grade <= grade_pass_temp;
		end
	
	wire clear_again = (g_Q == result) && ~KEY[1];
	 
	 // clearing the board
	 reg [8:0] cx; // holds 319
	 reg [7:0] cy; // holds 239
	 
	 always @ (posedge CLOCK_50)
		if(!KEY[0] || clear_again)
		begin
			clearing <= 1'b1;
			cx <= 9'b0;
			cy <= 8'b0;
		end
		else if(clearing)
		begin
			if(cx == 9'd319)
			begin
				cx <= 9'd0;
				if(cy == 9'd239)
				begin
					cy <= 8'd0;
					clearing <= 1'b0;
				end
				else
					cy <= cy + 1'b1;
			end
			else
				cx <= cx + 1'b1;
		end
		

    // these counter are used to generate pixel coordinates for the box
    Up_count U1 ({nX{1'd0}}, CLOCK_50, KEY[0], Lxc, Exc, XC);
        defparam U1.n = nX;
    Up_count U2 ({nY{1'd0}}, CLOCK_50, KEY[0], Lyc, Eyc, YC);
        defparam U2.n = nY;

    assign go = (g_Q == draw);

    // FSM state table
    always @ (*)
        case (y_Q)
            A:  if (!go || clearing) Y_D = A;
                else Y_D = B;
            B:  if (XC != size-1) Y_D = B;  // box x coordinate (column)
                else Y_D = C;
            C:  if (YC != size-1) Y_D = B;  // box y coordinate (row)
                else Y_D = D;
            D:  Y_D = A;
        endcase
    // FSM outputs
    always @ (*)
    begin
        // default assignments
        write = 1'b0; Lxc = 1'b0; Lyc = 1'b0; Exc = 1'b0; Eyc = 1'b0;
        case (y_Q)
            A:  begin Lxc = 1'b1; Lyc = 1'b1; end   // load (XC,YC) counter
            B:  begin Exc = 1'b1; write = 1'b1; end // enable XC, write pixel
            C:  begin Lxc = 1'b1; Eyc = 1'b1; end   // enable YC, load XC
            D:  Lyc = 1'b1;                         // load YC
        endcase
    end

    always @(posedge CLOCK_50)
        if (!KEY[0])
            y_Q <= 2'b0;
        else
            y_Q <= Y_D;
				
	 // drawing from memory stuff	 
	 
	 wire[8:0] color1, color2, color3;
	 object_mem shape1({YC[5:0], XC[5:0]}, CLOCK_50, color1);
		defparam shape1.n = 9;
		defparam shape1.Mn = 12;
		defparam shape1.INIT_FILE = "./MIF/shape1.mif";
	 object_mem shape2({YC[5:0], XC[5:0]}, CLOCK_50, color2);
		defparam shape2.n = 9;
		defparam shape2.Mn = 12;
		defparam shape2.INIT_FILE = "./MIF/shape2.mif";
	 object_mem shape3({YC[5:0], XC[5:0]}, CLOCK_50, color3);
		defparam shape3.n = 9;
		defparam shape3.Mn = 12;
		defparam shape3.INIT_FILE = "./MIF/shape3.mif";
	 
	 reg [8:0] obj_color;
	  always @(*) begin
		if (SW[0])
        obj_color = color1;
		else if (SW[1])
        obj_color = color2;
		else if (SW[2])
        obj_color = color3;
		else
        obj_color = 9'b000000000;
		end
	
		
	 wire[8:0] bg_color;
	 wire [16:0] bg_address = ({9'b0, cy} << 8) + ({9'b0, cy} << 6) + {8'b0, cx};
	 object_mem bg(bg_address, CLOCK_50, bg_color);
		defparam bg.n = 9;
		defparam bg.Mn = 17;
		defparam bg.INIT_FILE = "./MIF/background2.mif";
		
	 // colour printed is delayed by one cycle, so location of pixel (x, y) and write are delayed by one cycle
	 wire[nX-1:0] VGA_x;
	 wire[nY-1:0] VGA_y;
	 wire VGA_write;
	 wire VGA_clear;
	 
	 wire[nX-1:0] x0 = clearing ? {1'b0, cx} : (X - (size >> 1) + XC);
	 wire[nY-1:0] y0 = clearing ? {1'b0, cy} : (Y - (size >> 1) + YC);
	 
	 regn #(.n(nX)) RX (x0, KEY[0], 1'b1, CLOCK_50, VGA_x);
	 regn #(.n(nY)) RY (y0, KEY[0], 1'b1, CLOCK_50, VGA_y);
	 regn #(.n(1)) RW (write, KEY[0], 1'b1, CLOCK_50, VGA_write);
	 regn #(.n(1)) RC (clearing, KEY[0], 1'b1, CLOCK_50, VGA_clear);
	
	wire draw_pixel, pixel_write;
	wire [8:0] pixel_color;
	
	assign draw_pixel = VGA_write & obj_color != 9'b000000000;
	assign pixel_write = VGA_clear | draw_pixel;
	assign pixel_color = VGA_clear ? bg_color : obj_color;
	
	wire clear_count = (y_Q == A) & go;
	wire[3:0] d4, d3, d2, d1, d0;
	
	bcd_count5 UP (CLOCK_50, KEY[0], clear_count, draw_pixel, d4, d3, d2, d1, d0);
	
	hex7seg H4 (d4, HEX4);
    hex7seg H3 (d3, HEX3);
    hex7seg H2 (d2, HEX2);
    hex7seg H1 (d1, HEX1);
    hex7seg H0 (d0, HEX0);
	
	assign LEDR[8] = (g_Q == result) &  grade;   // PASS
   assign LEDR[9] = (g_Q == result) & ~grade;   // FAIL

    vga_adapter VGA (
        .resetn(1'b1), // we are not using vga adaptor reset so to prevent errors, we set reset to always 1
        .clock(CLOCK_50),
        .color(pixel_color),
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
