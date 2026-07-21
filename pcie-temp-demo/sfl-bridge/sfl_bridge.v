// Serial Flash Loader bridge for the Catapult v3 Arria 10.
//
// Arria 10 exposes three fixed ASMI chip-select lines.  The Catapult v3 uses
// CS0 for its single configuration flash; CS1 and CS2 are not populated.
// Drive the dedicated ASMI primitive directly so no shared-access handshake
// or user I/O pin is involved.

module sfl_bridge;

	wire       sfl_dclk;
	wire [2:0] sfl_sce;
	wire       sfl_data0_out;
	wire       sfl_data1_out;
	wire       sfl_data2_out;
	wire       sfl_data3_out;
	wire       sfl_data0_oe;
	wire       sfl_data1_oe;
	wire       sfl_data2_oe;
	wire       sfl_data3_oe;
	wire       flash_data0_in;
	wire       flash_data1_in;
	wire       flash_data2_in;
	wire       flash_data3_in;
	wire       sfl_access_request;

	alt_sfl_enhanced #(
		.QUAD_SPI_SUPPORT (1),
		.NCSO_WIDTH       (3)
	) sfl_inst (
		.dclkin              (sfl_dclk),
		.scein               (sfl_sce),
		.sdoin               (sfl_data0_out),
		.data1in             (sfl_data1_out),
		.data2in             (sfl_data2_out),
		.data3in             (sfl_data3_out),
		.data0oe             (sfl_data0_oe),
		.data1oe             (sfl_data1_oe),
		.data2oe             (sfl_data2_oe),
		.data3oe             (sfl_data3_oe),
		.asmi_access_request (sfl_access_request),
		.data0out            (flash_data0_in),
		.data1out            (flash_data1_in),
		.data2out            (flash_data2_in),
		.data3out            (flash_data3_in),
		.asmi_access_granted (1'b1)
	);

	// Dedicated configuration-flash access: active-low OE is asserted only in
	// this SRAM bridge image.  No user I/O pin is assigned or driven.
	twentynm_asmiblock asmi_inst (
		.dclk     (sfl_dclk),
		.sce      (sfl_sce),
		.oe       (1'b0),
		.data0out (sfl_data0_out),
		.data1out (sfl_data1_out),
		.data2out (sfl_data2_out),
		.data3out (sfl_data3_out),
		.data0oe  (sfl_data0_oe),
		.data1oe  (sfl_data1_oe),
		.data2oe  (sfl_data2_oe),
		.data3oe  (sfl_data3_oe),
		.data0in  (flash_data0_in),
		.data1in  (flash_data1_in),
		.data2in  (flash_data2_in),
		.data3in  (flash_data3_in)
	);

endmodule
