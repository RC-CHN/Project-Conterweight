
module TopEntity (

		// ----------- CLOCKS --------------
		input         clk_u59,
		input 	     clk_y3,
		input 	     clk_y4,

		// ------------ LEDS ---------------
		output [8:0]	leds,

		// ---------- DDR4 Top Interface -----------
		input         emif_top_oct_oct_rzqin,
		output [0:0]  emif_top_mem_mem_ck,
		output [0:0]  emif_top_mem_mem_ck_n,
		output [16:0] emif_top_mem_mem_a,
		output [0:0]  emif_top_mem_mem_act_n,
		output [1:0]  emif_top_mem_mem_ba,
		output [0:0]  emif_top_mem_mem_bg,
		output [0:0]  emif_top_mem_mem_cke,
		output [0:0]  emif_top_mem_mem_cs_n,
		output [0:0]  emif_top_mem_mem_odt,
		output [0:0]  emif_top_mem_mem_reset_n,
		output [0:0]  emif_top_mem_mem_par,
		input  [0:0]  emif_top_mem_mem_alert_n,
		inout  [8:0]  emif_top_mem_mem_dqs,
		inout  [8:0]  emif_top_mem_mem_dqs_n,
		inout  [71:0] emif_top_mem_mem_dq,
		inout  [8:0]  emif_top_mem_mem_dbi_n,

		// ---------- DDR4 Bottom Interface -----------
		input         emif_bot_oct_oct_rzqin,
		output [0:0]  emif_bot_mem_mem_ck,
		output [0:0]  emif_bot_mem_mem_ck_n,
		output [16:0] emif_bot_mem_mem_a,
		output [0:0]  emif_bot_mem_mem_act_n,
		output [1:0]  emif_bot_mem_mem_ba,
		output [0:0]  emif_bot_mem_mem_bg,
		output [0:0]  emif_bot_mem_mem_cke,
		output [0:0]  emif_bot_mem_mem_cs_n,
		output [0:0]  emif_bot_mem_mem_odt,
		output [0:0]  emif_bot_mem_mem_reset_n,
		output [0:0]  emif_bot_mem_mem_par,
		input  [0:0]  emif_bot_mem_mem_alert_n,
		inout  [8:0]  emif_bot_mem_mem_dqs,
		inout  [8:0]  emif_bot_mem_mem_dqs_n,
		inout  [71:0] emif_bot_mem_mem_dq,
		inout  [8:0]  emif_bot_mem_mem_dbi_n

);

reg [31:0] alive_count;
wire top_cal_success;
wire top_cal_fail;
wire top_pll_locked;
wire top_ecc_interrupt;
wire bot_cal_success;
wire bot_cal_fail;
wire bot_pll_locked;
wire bot_ecc_interrupt;
wire [2:0] bist_source_raw;
wire bandwidth_source_unused;
// Quartus 22.1's VHDL altsource_probe implementation rejects an all-zero
// SOURCE_INITIAL_VALUE for this instance.  Keep its known-good raw value of
// 3, then invert the two enable bits so the logical BIST control still powers
// up at 0 (both engines stopped).  System Console applies the inverse mapping
// on writes; all probe/status consumers see only the logical value.
wire [2:0] bist_control = bist_source_raw ^ 3'b011;

wire top_bist_running;
wire [3:0] top_bist_state;
wire [1:0] top_bist_pattern;
wire [31:0] top_bist_heartbeat_gray;
wire [31:0] top_bist_pass_count_gray;
wire [31:0] top_bist_error_count_gray;
wire [24:0] top_bist_address_gray;
wire [24:0] top_bist_first_error_address;
wire [63:0] top_bist_error_byte_mask;
wire [63:0] top_bist_last_write_cycles_gray;
wire [63:0] top_bist_last_read_cycles_gray;

wire bot_bist_running;
wire [3:0] bot_bist_state;
wire [1:0] bot_bist_pattern;
wire [31:0] bot_bist_heartbeat_gray;
wire [31:0] bot_bist_pass_count_gray;
wire [31:0] bot_bist_error_count_gray;
wire [24:0] bot_bist_address_gray;
wire [24:0] bot_bist_first_error_address;
wire [63:0] bot_bist_error_byte_mask;
wire [63:0] bot_bist_last_write_cycles_gray;
wire [63:0] bot_bist_last_read_cycles_gray;

wire [31:0] alive_count_gray = alive_count ^ (alive_count >> 1);

// On-die temperature capture.  The System Console conversion is
// T(C) = 693 * code / 1024 - 265, matching the working PCIe/QSFP designs.
wire [9:0] temp_raw_wire;
wire       temp_eoc;
reg        temp_eoc_meta;
reg        temp_eoc_sync;
reg        temp_eoc_prev;
reg [9:0]  temp_code;
reg        temp_valid;

altera_temp_sense temp_sensor (
	.corectl(1'b1),
	.reset(1'b0),
	.eoc(temp_eoc),
	.tempout(temp_raw_wire)
);

always @(posedge clk_u59) begin
	temp_eoc_meta <= temp_eoc;
	temp_eoc_sync <= temp_eoc_meta;
	temp_eoc_prev <= temp_eoc_sync;
	if (temp_eoc_prev && !temp_eoc_sync) begin
		temp_code <= temp_raw_wire;
		temp_valid <= 1'b1;
	end
end

// Probe layout, least-significant field first:
//   [31:0]    U59 100 MHz Gray counter
//   [63:32]   bottom EMIF user-clock Gray counter
//   [95:64]   top EMIF user-clock Gray counter
//   [96]      top calibration success
//   [97]      top calibration failure
//   [98]      top PLL locked
//   [99]      bottom calibration success
//   [100]     bottom calibration failure
//   [101]     bottom PLL locked
//   [102]     top ECC interrupt
//   [103]     bottom ECC interrupt
//   [106:104] BIST source/control readback: {clear, bottom enable, top enable}
//   [291:107] top BIST status
//   [476:292] bottom BIST status
//   [477]     on-die temperature valid
//   [487:478] on-die temperature raw code
//
// Each 185-bit BIST status is packed least-significant field first as:
//   running[0], state[4:1], pattern[6:5], pass Gray[38:7],
//   error Gray[70:39], address Gray[95:71], first-error address[120:96],
//   byte-error mask[184:121].
wire [487:0] ddr4_probe_data = {
	temp_code,
	temp_valid,
	bot_bist_error_byte_mask,
	bot_bist_first_error_address,
	bot_bist_address_gray,
	bot_bist_error_count_gray,
	bot_bist_pass_count_gray,
	bot_bist_pattern,
	bot_bist_state,
	bot_bist_running,
	top_bist_error_byte_mask,
	top_bist_first_error_address,
	top_bist_address_gray,
	top_bist_error_count_gray,
	top_bist_pass_count_gray,
	top_bist_pattern,
	top_bist_state,
	top_bist_running,
	bist_control,
	bot_ecc_interrupt,
	top_ecc_interrupt,
	bot_pll_locked,
	bot_cal_fail,
	bot_cal_success,
	top_pll_locked,
	top_cal_fail,
	top_cal_success,
	top_bist_heartbeat_gray,
	bot_bist_heartbeat_gray,
	alive_count_gray
};

// A second ISSP instance keeps the original 488-bit status ABI intact and
// stays below the Quartus 22.1 per-instance maximum probe width of 511 bits.
// Least-significant field first: top write, top read, bottom write, bottom read.
wire [255:0] ddr4_bandwidth_probe_data = {
	bot_bist_last_read_cycles_gray,
	bot_bist_last_write_cycles_gray,
	top_bist_last_read_cycles_gray,
	top_bist_last_write_cycles_gray
};

assign leds[6] = top_bist_heartbeat_gray[27];
assign leds[7] = bot_bist_heartbeat_gray[27];
assign leds[8] = alive_count[25];
assign leds[0] = top_cal_success;
assign leds[1] = top_cal_fail;
assign leds[2] = top_pll_locked;
assign leds[3] = bot_cal_success;
assign leds[4] = bot_cal_fail;
assign leds[5] = bot_pll_locked;


always @ (posedge clk_u59)
begin
alive_count <= alive_count + 1'b1;
end

// Leave both BIST engines stopped after configuration.  The raw source starts
// at 3 and maps to logical control 0.  Memory traffic starts only after System
// Console verifies calibration, ECC state and temperature.
altsource_probe #(
	.sld_auto_instance_index("YES"),
	.sld_instance_index(0),
	.instance_id("DDR4"),
	.probe_width(488),
	.source_width(3),
	.source_initial_value("3"),
	.enable_metastability("YES")
) ddr4_status_probe (
	.probe(ddr4_probe_data),
	.source(bist_source_raw),
	.source_clk(clk_u59),
	.source_ena(1'b1)
);

altsource_probe #(
	.sld_auto_instance_index("YES"),
	.sld_instance_index(0),
	.instance_id("DDRB"),
	.probe_width(256),
	.source_width(1),
	.source_initial_value("1"),
	.enable_metastability("YES")
) ddr4_bandwidth_probe (
	.probe(ddr4_bandwidth_probe_data),
	.source(bandwidth_source_unused),
	.source_clk(clk_u59),
	.source_ena(1'b0)
);

initial begin
	alive_count = 0;
	temp_eoc_meta = 1'b0;
	temp_eoc_sync = 1'b0;
	temp_eoc_prev = 1'b0;
	temp_code = 10'd0;
	temp_valid = 1'b0;
end


	Qsys u0 (
		// --------Full-aperture BIST controls and status
		.bist_top_control_enable (bist_control[0]),
		.bist_top_control_clear  (bist_control[2]),
		.bist_top_status_running (top_bist_running),
		.bist_top_status_state (top_bist_state),
		.bist_top_status_pattern (top_bist_pattern),
		.bist_top_status_heartbeat_gray (top_bist_heartbeat_gray),
		.bist_top_status_pass_count_gray (top_bist_pass_count_gray),
		.bist_top_status_error_count_gray (top_bist_error_count_gray),
		.bist_top_status_address_gray (top_bist_address_gray),
		.bist_top_status_first_error_address (top_bist_first_error_address),
		.bist_top_status_error_byte_mask (top_bist_error_byte_mask),
		.bist_top_status_last_write_cycles_gray (top_bist_last_write_cycles_gray),
		.bist_top_status_last_read_cycles_gray (top_bist_last_read_cycles_gray),

		.bist_bot_control_enable (bist_control[1]),
		.bist_bot_control_clear  (bist_control[2]),
		.bist_bot_status_running (bot_bist_running),
		.bist_bot_status_state (bot_bist_state),
		.bist_bot_status_pattern (bot_bist_pattern),
		.bist_bot_status_heartbeat_gray (bot_bist_heartbeat_gray),
		.bist_bot_status_pass_count_gray (bot_bist_pass_count_gray),
		.bist_bot_status_error_count_gray (bot_bist_error_count_gray),
		.bist_bot_status_address_gray (bot_bist_address_gray),
		.bist_bot_status_first_error_address (bot_bist_first_error_address),
		.bist_bot_status_error_byte_mask (bot_bist_error_byte_mask),
		.bist_bot_status_last_write_cycles_gray (bot_bist_last_write_cycles_gray),
		.bist_bot_status_last_read_cycles_gray (bot_bist_last_read_cycles_gray),

		// --------CLOCKS
		.clk_100_clk            (clk_u59),            	  //    clk_100.clk

		// --------DDR4 Top
		.emif_top_pll_ref_clk_clk (clk_y4),                   //      emif_top_pll_ref_clk.clk
		.emif_top_ctrl_ecc_user_interrupt_0_ctrl_ecc_user_interrupt (top_ecc_interrupt),
		.emif_top_mem_mem_ck      (emif_top_mem_mem_ck),      // 	  emif_top_mem.mem_ck
		.emif_top_mem_mem_ck_n    (emif_top_mem_mem_ck_n),    //           .mem_ck_n
		.emif_top_mem_mem_a       (emif_top_mem_mem_a),       //           .mem_a
		.emif_top_mem_mem_act_n   (emif_top_mem_mem_act_n),   //           .mem_act_n
		.emif_top_mem_mem_ba      (emif_top_mem_mem_ba),      //           .mem_ba
		.emif_top_mem_mem_bg      (emif_top_mem_mem_bg),      //           .mem_bg
		.emif_top_mem_mem_cke     (emif_top_mem_mem_cke),     //           .mem_cke
		.emif_top_mem_mem_cs_n    (emif_top_mem_mem_cs_n),    //           .mem_cs_n
		.emif_top_mem_mem_odt     (emif_top_mem_mem_odt),     //           .mem_odt
		.emif_top_mem_mem_reset_n (emif_top_mem_mem_reset_n), //           .mem_reset_n
		.emif_top_mem_mem_par     (emif_top_mem_mem_par),     //           .mem_par
		.emif_top_mem_mem_alert_n (emif_top_mem_mem_alert_n), //           .mem_alert_n
		.emif_top_mem_mem_dqs     (emif_top_mem_mem_dqs),     //           .mem_dqs
		.emif_top_mem_mem_dqs_n   (emif_top_mem_mem_dqs_n),   //           .mem_dqs_n
		.emif_top_mem_mem_dq      (emif_top_mem_mem_dq),      //           .mem_dq
		.emif_top_mem_mem_dbi_n   (emif_top_mem_mem_dbi_n),   //           .mem_dbi_n
		.emif_top_oct_oct_rzqin   (emif_top_oct_oct_rzqin),   // 	  emif_top_oct.oct_rzqin
		.emif_top_status_local_cal_success (top_cal_success),	//	  	  emif_top_status.local_cal_success
		.emif_top_status_local_cal_fail    (top_cal_fail),		//              .local_cal_fail
		.emif_top_pll_locked_conduit_end_pll_locked(top_pll_locked),

		// --------DDR4 Bottom
		.emif_bot_pll_ref_clk_clk (clk_y3),                   //      emif_bot_pll_ref_clk.clk
		.emif_bot_ctrl_ecc_user_interrupt_0_ctrl_ecc_user_interrupt (bot_ecc_interrupt),
		.emif_bot_mem_mem_ck      (emif_bot_mem_mem_ck),      // 	  emif_bot_mem.mem_ck
		.emif_bot_mem_mem_ck_n    (emif_bot_mem_mem_ck_n),    //           .mem_ck_n
		.emif_bot_mem_mem_a       (emif_bot_mem_mem_a),       //           .mem_a
		.emif_bot_mem_mem_act_n   (emif_bot_mem_mem_act_n),   //           .mem_act_n
		.emif_bot_mem_mem_ba      (emif_bot_mem_mem_ba),      //           .mem_ba
		.emif_bot_mem_mem_bg      (emif_bot_mem_mem_bg),      //           .mem_bg
		.emif_bot_mem_mem_cke     (emif_bot_mem_mem_cke),     //           .mem_cke
		.emif_bot_mem_mem_cs_n    (emif_bot_mem_mem_cs_n),    //           .mem_cs_n
		.emif_bot_mem_mem_odt     (emif_bot_mem_mem_odt),     //           .mem_odt
		.emif_bot_mem_mem_reset_n (emif_bot_mem_mem_reset_n), //           .mem_reset_n
		.emif_bot_mem_mem_par     (emif_bot_mem_mem_par),     //           .mem_par
		.emif_bot_mem_mem_alert_n (emif_bot_mem_mem_alert_n), //           .mem_alert_n
		.emif_bot_mem_mem_dqs     (emif_bot_mem_mem_dqs),     //           .mem_dqs
		.emif_bot_mem_mem_dqs_n   (emif_bot_mem_mem_dqs_n),   //           .mem_dqs_n
		.emif_bot_mem_mem_dq      (emif_bot_mem_mem_dq),      //           .mem_dq
		.emif_bot_mem_mem_dbi_n   (emif_bot_mem_mem_dbi_n),   //           .mem_dbi_n
		.emif_bot_oct_oct_rzqin   (emif_bot_oct_oct_rzqin),   // 	  emif_bot_oct.oct_rzqin
		.emif_bot_status_local_cal_success (bot_cal_success),	//	     emif_bot_status.local_cal_success
		.emif_bot_status_local_cal_fail    (bot_cal_fail),		//              .local_cal_fail
		.emif_bot_pll_locked_conduit_end_pll_locked(bot_pll_locked)
	);


endmodule
