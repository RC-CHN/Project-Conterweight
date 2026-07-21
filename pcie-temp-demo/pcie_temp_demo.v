
module pcie_temp_demo (

		// CLOCKS
		input         clk_u59,
		input 	     clk_y3,
		input 	     clk_y4,
		input			  clk_y5,
		input			  clk_y6,
		input			  clk_pcie1,
		input			  clk_pcie2,
		
		// LEDs
		output [8:0] leds,
		
		// PCIe Interface#1
		input           pcie1_perstn,
		input  [ 7:0]   pcie1_rx,
		output [ 7:0]   pcie1_tx
);

	reg [31:0] alive_count;
	reg        temp_eoc_meta;
	reg        temp_eoc_sync;
	reg        temp_eoc_prev;
	reg [9:0]  temp_code;
	reg        temp_valid;
	wire       temp_eoc;
	wire [9:0] temp_raw;
	wire [31:0] debug_control;

	assign leds[7:0] = debug_control[7:0];
	assign leds[8] = alive_count[25];
	
	always @ (posedge clk_u59)
	begin
		alive_count <= alive_count + 1'b1;
		temp_eoc_meta <= temp_eoc;
		temp_eoc_sync <= temp_eoc_meta;
		temp_eoc_prev <= temp_eoc_sync;

		if (temp_eoc_prev && !temp_eoc_sync) begin
			temp_code <= temp_raw;
			temp_valid <= 1'b1;
		end
	end

	initial begin
		alive_count   = 32'd0;
		temp_eoc_meta = 1'b0;
		temp_eoc_sync = 1'b0;
		temp_eoc_prev = 1'b0;
		temp_code     = 10'd0;
		temp_valid    = 1'b0;
	end

	altera_temp_sense temp_sensor (
		.corectl (1'b1),
		.reset   (1'b0),
		.eoc     (temp_eoc),
		.tempout (temp_raw)
	);
	
	Qsys u0 (
	
		// ------ CLOCKS --------
		.clk_100_clk                       (clk_u59),
		
		//---------- PCIe Interface#1	--------
		.pcie_a10_hip_1_refclk_clk         (clk_pcie1),
		.pcie_a10_hip_1_npor_npor          (1'b1),
		.pcie_a10_hip_1_npor_pin_perst     (pcie1_perstn),
		.pcie_a10_hip_1_hip_serial_rx_in0  (pcie1_rx[0]), 
		.pcie_a10_hip_1_hip_serial_rx_in1  (pcie1_rx[1]), 
		.pcie_a10_hip_1_hip_serial_rx_in2  (pcie1_rx[2]), 
		.pcie_a10_hip_1_hip_serial_rx_in3  (pcie1_rx[3]), 
		.pcie_a10_hip_1_hip_serial_rx_in4  (pcie1_rx[4]), 
		.pcie_a10_hip_1_hip_serial_rx_in5  (pcie1_rx[5]), 
		.pcie_a10_hip_1_hip_serial_rx_in6  (pcie1_rx[6]), 
		.pcie_a10_hip_1_hip_serial_rx_in7  (pcie1_rx[7]), 
		.pcie_a10_hip_1_hip_serial_tx_out0 (pcie1_tx[0]), 
		.pcie_a10_hip_1_hip_serial_tx_out1 (pcie1_tx[1]), 
		.pcie_a10_hip_1_hip_serial_tx_out2 (pcie1_tx[2]), 
		.pcie_a10_hip_1_hip_serial_tx_out3 (pcie1_tx[3]), 
		.pcie_a10_hip_1_hip_serial_tx_out4 (pcie1_tx[4]), 
		.pcie_a10_hip_1_hip_serial_tx_out5 (pcie1_tx[5]), 
		.pcie_a10_hip_1_hip_serial_tx_out6 (pcie1_tx[6]), 
		.pcie_a10_hip_1_hip_serial_tx_out7 (pcie1_tx[7]), 
		.pcie_a10_hip_1_coreclkout_hip_clk (),
		
		// BAR0 register file. Each PIO occupies a 16-byte Avalon-MM span.
		.debug_id_external_connection_export     (32'h43505433),
		.debug_status_external_connection_export (alive_count),
		.debug_temp_external_connection_export   ({21'd0, temp_valid, temp_code}),
		.pio_0_external_connection_export        (debug_control)
		);



endmodule 
