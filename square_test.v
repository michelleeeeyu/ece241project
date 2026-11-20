module square_test(CLOCK_50, KEY, VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N,  VGA_CLK);

	input CLOCK_50;
	input[3:0] KEY;
	output [7:0] VGA_R;
	output [7:0] VGA_G;
	output [7:0] VGA_B;
	output VGA_HS;
	output VGA_VS;
	output VGA_BLANK_N;
	output VGA_SYNC_N;
	output VGA_CLK;
	
	// the square
	parameter side = 100;
	parameter x0 = 320 - side / 2;
	parameter y0 = 240 - side / 2;
	parameter color = 9'b111_101_110;
	
	// counter that walks over each pixel of the square
	reg [9:0] xcount;
	reg [8:0] ycount;
	reg done;
	
	always @ (posedge CLOCK_50)
		if(!KEY[0])
		begin
			xcount <= 10'b0;
			ycount <= 9'b0;
			done <= 0;
		end
		else if(!done) 
		begin
			if(xcount == side - 1) 
				xcount <= 10'b0;
				if(ycount == side - 1)
					done <= 1'b1;
				else
					ycount <= ycount + 9'd1;
			end
			else
				xcount <= xcount + 10'd1;
				
	wire[9:0] x = x0 + xc;
	wire[8:0] y = y0 + yc;
	wire enable = ~done;

	vga_adapter VGA (
		.resetn(KEY[0]),
		.clock(CLOCK_50),
		.color(color),
		.x(x),
		.y(y),
		.write(enable),
		.VGA_R(VGA_R),
		.VGA_G(VGA_G),
		.VGA_B(VGA_B),
		.VGA_HS(VGA_HS),
		.VGA_VS(vGA_VS),
		.VGA_BLANK_N(VGA_BLANK_N),
		.VGA_SYNC_N(VGA_SYNC_N),
		.VGA_CLK(VGA_CLK) );

endmodule