/* object_mem
 * ----------
 * Read-only memory that holds the pixels of a template image, loaded from a MIF file
 * when the FPGA is programmed. It has 2^Mn words of n bits each (one word per pixel,
 * stored row by row: address = {row, column}).
 *
 * The address is registered inside the memory, so the pixel color for an address
 * appears on q one clock cycle after the address is applied.
 */
module object_mem (address, clock, q);
    parameter n = 9;                                    // bits per pixel (color depth)
    parameter Mn = 10;                                  // address bits: 2^Mn pixels
    parameter INIT_FILE = "./MIF/template_32x32_9.mif"; // pixel data

    input wire [Mn-1:0] address;
    input wire clock;
    output wire [n-1:0] q;

    altsyncram ROM (
        .address_a (address),
        .clock0 (clock),
        .q_a (q)
    );
    defparam
        ROM.operation_mode = "ROM",
        ROM.intended_device_family = "Cyclone V",
        ROM.width_a = n,
        ROM.widthad_a = Mn,
        ROM.numwords_a = (1 << Mn),
        ROM.outdata_reg_a = "UNREGISTERED",
        ROM.clock_enable_input_a = "BYPASS",
        ROM.clock_enable_output_a = "BYPASS",
        ROM.power_up_uninitialized = "FALSE",
        ROM.init_file = INIT_FILE;
endmodule
