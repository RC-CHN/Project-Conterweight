
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

reg [31:0] top_count;
reg [31:0] bot_count;
reg [31:0] alive_count;
wire top_mem_clk;
wire bot_mem_clk;
wire top_cal_success;
wire top_cal_fail;
wire top_pll_locked;
wire top_ecc_interrupt;
wire bot_cal_success;
wire bot_cal_fail;
wire bot_pll_locked;
wire bot_ecc_interrupt;

wire [31:0] top_count_gray = top_count ^ (top_count >> 1);
wire [31:0] bot_count_gray = bot_count ^ (bot_count >> 1);
wire [31:0] alive_count_gray = alive_count ^ (alive_count >> 1);

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
wire [103:0] ddr4_probe_data = {
	bot_ecc_interrupt,
	top_ecc_interrupt,
	bot_pll_locked,
	bot_cal_fail,
	bot_cal_success,
	top_pll_locked,
	top_cal_fail,
	top_cal_success,
	top_count_gray,
	bot_count_gray,
	alive_count_gray
};

assign leds[6] = top_count[27];
assign leds[7] = bot_count[27];
assign leds[8] = alive_count[25];
assign leds[0] = top_cal_success;
assign leds[1] = top_cal_fail;
assign leds[2] = top_pll_locked;
assign leds[3] = bot_cal_success;
assign leds[4] = bot_cal_fail;
assign leds[5] = bot_pll_locked;


always @ (posedge top_mem_clk)
begin
top_count <= top_count + 1'b1;
end

always @ (posedge bot_mem_clk)
begin
bot_count <= bot_count + 1'b1;
end

always @ (posedge clk_u59)
begin
alive_count <= alive_count + 1'b1;
end

altsource_probe #(
	.sld_auto_instance_index("YES"),
	.sld_instance_index(0),
	.instance_id("DDR4"),
	.probe_width(104),
	.source_width(0),
	.enable_metastability("YES")
) ddr4_status_probe (
	.probe(ddr4_probe_data)
);

initial begin
	top_count = 0;
	bot_count = 0;
	alive_count = 0;
end


	Qsys u0 (
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
		.emif_top_emif_usr_clk_clk(top_mem_clk),
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
		.emif_bot_emif_usr_clk_clk(bot_mem_clk),
		.emif_bot_pll_locked_conduit_end_pll_locked(bot_pll_locked)
	);


endmodule
