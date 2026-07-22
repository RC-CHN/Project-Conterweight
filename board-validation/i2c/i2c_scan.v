// Catapult v3 dual-I2C read-only discovery design.
//
// The board pins can only be pulled low or released. There is deliberately no
// RTL path that can actively drive a logic high onto either 1.8 V bus.

module i2c_scan (
    input  wire clk_u59,
    inout  wire scl_ch1,
    inout  wire sda_ch1,
    inout  wire scl_ch2,
    inout  wire sda_ch2
);

    wire ch1_sda_controller_oe;
    wire ch1_scl_controller_oe;
    wire ch2_sda_controller_oe;
    wire ch2_scl_controller_oe;

    // JTAG-controlled bus recovery is disabled after configuration. When it is
    // explicitly enabled, the controller OEs are isolated and each line can
    // still only be pulled low or released through the same I/O atoms.
    // recovery_source[4:0] = {ch2 SDA, ch2 SCL, ch1 SDA, ch1 SCL, enable}
    wire [4:0] recovery_source;
    wire recovery_enable = recovery_source[0];
    wire ch1_scl_oe = recovery_enable ? recovery_source[1] : ch1_scl_controller_oe;
    wire ch1_sda_oe = recovery_enable ? recovery_source[2] : ch1_sda_controller_oe;
    wire ch2_scl_oe = recovery_enable ? recovery_source[3] : ch2_scl_controller_oe;
    wire ch2_sda_oe = recovery_enable ? recovery_source[4] : ch2_sda_controller_oe;

    wire ch1_scl_in;
    wire ch1_sda_in;
    wire ch2_scl_in;
    wire ch2_sda_in;

    // Explicit Arria 10 I/O atoms make the constant-low data input and dynamic
    // output enable auditable in the post-fit Bidir Pins report. This avoids an
    // ambiguous warning emitted by Quartus for inferred `0 : Z` assignments.
    i2c_open_drain_iobuf scl_ch1_buffer (
        .drive_low(ch1_scl_oe), .sample(ch1_scl_in), .pad(scl_ch1));
    i2c_open_drain_iobuf sda_ch1_buffer (
        .drive_low(ch1_sda_oe), .sample(ch1_sda_in), .pad(sda_ch1));
    i2c_open_drain_iobuf scl_ch2_buffer (
        .drive_low(ch2_scl_oe), .sample(ch2_scl_in), .pad(scl_ch2));
    i2c_open_drain_iobuf sda_ch2_buffer (
        .drive_low(ch2_sda_oe), .sample(ch2_sda_in), .pad(sda_ch2));

    // Hold the Platform Designer system in reset for the first 256 U59 clock
    // cycles after FPGA configuration, then synchronously release it.
    reg [7:0] por_count;
    wire reset_n = &por_count;
    always @(posedge clk_u59) begin
        if (!reset_n)
            por_count <= por_count + 1'b1;
    end

    i2c_bridge bridge (
        .clk_100_clk    (clk_u59),
        .i2c_ch1_sda_in (ch1_sda_in),
        .i2c_ch1_scl_in (ch1_scl_in),
        .i2c_ch1_sda_oe (ch1_sda_controller_oe),
        .i2c_ch1_scl_oe (ch1_scl_controller_oe),
        .i2c_ch2_sda_in (ch2_sda_in),
        .i2c_ch2_scl_in (ch2_scl_in),
        .i2c_ch2_sda_oe (ch2_sda_controller_oe),
        .i2c_ch2_scl_oe (ch2_scl_controller_oe),
        .reset_reset_n  (reset_n)
    );

    // Synchronize the physical line levels solely for a pre-flight idle check.
    // Probe [3:0] = {ch2 SDA, ch2 SCL, ch1 SDA, ch1 SCL}
    // Probe [7:4] = {ch2 SDA OE, ch2 SCL OE, ch1 SDA OE, ch1 SCL OE}
    // Probe [8]   = reset_n
    // Probe [40:9] = free-running 100 MHz heartbeat
    reg [3:0] line_meta;
    reg [3:0] line_sync;
    reg [31:0] heartbeat;
    always @(posedge clk_u59) begin
        line_meta <= {ch2_sda_in, ch2_scl_in, ch1_sda_in, ch1_scl_in};
        line_sync <= line_meta;
        heartbeat <= heartbeat + 1'b1;
    end

    wire [40:0] probe_data = {
        heartbeat,
        reset_n,
        ch2_sda_oe,
        ch2_scl_oe,
        ch1_sda_oe,
        ch1_scl_oe,
        line_sync
    };

    altsource_probe #(
        .sld_auto_instance_index("YES"),
        .sld_instance_index(0),
        .instance_id("I2CS"),
        .probe_width(41),
        .source_width(5),
        .source_initial_value("0"),
        .enable_metastability("YES")
    ) line_probe (
        .probe(probe_data),
        .source(recovery_source),
        .source_clk(clk_u59),
        .source_ena(1'b1)
    );

    initial begin
        por_count = 0;
        line_meta = 0;
        line_sync = 0;
        heartbeat = 0;
    end

endmodule

module i2c_open_drain_iobuf (
    input  wire drive_low,
    output wire sample,
    inout  wire pad
);

    twentynm_io_obuf #(
        .open_drain_output("false")
    ) output_buffer (
        .i(1'b0),
        .oe(drive_low),
        .o(pad),
        .obar(),
        .dynamicterminationcontrol(1'b0)
    );

    twentynm_io_ibuf input_buffer (
        .i(pad),
        .ibar(1'b0),
        .o(sample),
        .dynamicterminationcontrol(1'b0)
    );

endmodule
