// Catapult v3 QSFP management-plane validation.
//
// The management I2C pins can only be pulled low or released.  MODPRSL and
// the Y5 oscillator are input-only.  This image contains no transceiver, so it
// cannot drive a high-speed QSFP lane.

module qsfp_mgmt (
    input  wire clk_u59,
    input  wire clk_y5,
    input  wire modprsl,
    inout  wire scl_ch1,
    inout  wire sda_ch1
);

    wire scl_controller_oe;
    wire sda_controller_oe;

    // source[2:0] = {SDA pull-low, SCL pull-low, recovery enable}.
    // Recovery is disabled after configuration and is never used by the
    // ordinary inspection/read scripts.
    wire [2:0] recovery_source;
    wire recovery_enable = recovery_source[0];
    wire scl_oe = recovery_enable ? recovery_source[1] : scl_controller_oe;
    wire sda_oe = recovery_enable ? recovery_source[2] : sda_controller_oe;
    wire scl_in;
    wire sda_in;

    qsfp_open_drain_iobuf scl_buffer (
        .drive_low(scl_oe), .sample(scl_in), .pad(scl_ch1));
    qsfp_open_drain_iobuf sda_buffer (
        .drive_low(sda_oe), .sample(sda_in), .pad(sda_ch1));

    reg [7:0] por_count;
    wire reset_n = &por_count;
    always @(posedge clk_u59) begin
        if (!reset_n)
            por_count <= por_count + 1'b1;
    end

    i2c_bridge bridge (
        .clk_100_clk    (clk_u59),
        .i2c_ch1_sda_in (sda_in),
        .i2c_ch1_scl_in (scl_in),
        .i2c_ch1_sda_oe (sda_controller_oe),
        .i2c_ch1_scl_oe (scl_controller_oe),
        .reset_reset_n  (reset_n)
    );

    // Divide Y5 before its first synchronizer so the approximately 20.14 MHz
    // toggle rate can be counted reliably in the 100 MHz management domain.
    reg [5:0] y5_prescale;
    always @(posedge clk_y5)
        y5_prescale <= y5_prescale + 1'b1;

    reg y5_toggle_meta;
    reg y5_toggle_sync;
    reg y5_toggle_prev;
    reg modprsl_meta;
    reg modprsl_sync;
    reg scl_meta;
    reg scl_sync;
    reg sda_meta;
    reg sda_sync;
    reg [31:0] heartbeat;
    reg [31:0] y5_events;

    always @(posedge clk_u59) begin
        heartbeat <= heartbeat + 1'b1;
        y5_toggle_meta <= y5_prescale[5];
        y5_toggle_sync <= y5_toggle_meta;
        y5_toggle_prev <= y5_toggle_sync;
        y5_events <= y5_events + (y5_toggle_sync ^ y5_toggle_prev);
        modprsl_meta <= modprsl;
        modprsl_sync <= modprsl_meta;
        scl_meta <= scl_in;
        scl_sync <= scl_meta;
        sda_meta <= sda_in;
        sda_sync <= sda_meta;
    end

    wire [31:0] heartbeat_gray = heartbeat ^ (heartbeat >> 1);
    wire [31:0] y5_events_gray = y5_events ^ (y5_events >> 1);

    // Probe layout, least-significant field first:
    //   [0]       physical SCL level
    //   [1]       physical SDA level
    //   [2]       controller SCL OE
    //   [3]       controller SDA OE
    //   [4]       selected physical SCL OE
    //   [5]       selected physical SDA OE
    //   [6]       reset_n
    //   [7]       synchronized MODPRSL (0 means module present)
    //   [39:8]    100 MHz heartbeat Gray counter
    //   [71:40]   Y5 divided-edge Gray counter (delta x 32)
    //   [74:72]   recovery source readback
    wire [74:0] probe_data = {
        recovery_source,
        y5_events_gray,
        heartbeat_gray,
        modprsl_sync,
        reset_n,
        sda_oe,
        scl_oe,
        sda_controller_oe,
        scl_controller_oe,
        sda_sync,
        scl_sync
    };

    altsource_probe #(
        .sld_auto_instance_index("YES"),
        .sld_instance_index(0),
        .instance_id("QSM1"),
        .probe_width(75),
        .source_width(3),
        .source_initial_value("0"),
        .enable_metastability("YES")
    ) management_probe (
        .probe(probe_data),
        .source(recovery_source),
        .source_clk(clk_u59),
        .source_ena(1'b1)
    );

    initial begin
        por_count = 0;
        y5_prescale = 0;
        y5_toggle_meta = 0;
        y5_toggle_sync = 0;
        y5_toggle_prev = 0;
        modprsl_meta = 1;
        modprsl_sync = 1;
        scl_meta = 1;
        scl_sync = 1;
        sda_meta = 1;
        sda_sync = 1;
        heartbeat = 0;
        y5_events = 0;
    end

endmodule

module qsfp_open_drain_iobuf (
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
