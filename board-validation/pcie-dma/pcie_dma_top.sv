module pcie_dma_top (
    input  wire       pcie1_refclk,
    input  wire       pcie1_perstn,
    input  wire [7:0] pcie1_rx,
    output wire [7:0] pcie1_tx,
    output wire [8:0] leds
);

    localparam logic [31:0] DESIGN_ID    = 32'h4344_4d41; // "CDMA"
    localparam logic [31:0] ABI_VERSION  = 32'h0001_0000;
    localparam logic [31:0] CAPABILITIES = 32'h0014_000f;

    wire        core_clk;
    wire        app_reset_n;
    wire [31:0] scratch;

    logic [31:0] heartbeat;
    logic        perst_meta;
    logic        perst_sync;
    logic        perst_prev;
    logic        seen_perst_deassert;
    logic [31:0] reset_count;
    logic [31:0] error_count;

    initial begin
        heartbeat          = 32'd0;
        perst_meta          = 1'b0;
        perst_sync          = 1'b0;
        perst_prev          = 1'b0;
        seen_perst_deassert = 1'b0;
        reset_count         = 32'd0;
        error_count         = 32'd0;
    end

    always_ff @(posedge core_clk) begin
        heartbeat <= heartbeat + 1'b1;

        perst_meta <= pcie1_perstn;
        perst_sync <= perst_meta;
        perst_prev <= perst_sync;

        if (!perst_prev && perst_sync) begin
            reset_count         <= reset_count + 1'b1;
            seen_perst_deassert <= 1'b1;
        end

        if (perst_prev && !perst_sync && seen_perst_deassert)
            error_count <= error_count + 1'b1;
    end

    assign leds[0]   = heartbeat[25];
    assign leds[1]   = app_reset_n;
    assign leds[2]   = perst_sync;
    assign leds[7:3] = scratch[4:0];
    assign leds[8]   = |error_count;

    dma_system system (
        .hip_refclk_clk                          (pcie1_refclk),
        .hip_npor_npor                          (1'b1),
        .hip_npor_pin_perst                     (pcie1_perstn),
        .hip_hip_serial_rx_in0                  (pcie1_rx[0]),
        .hip_hip_serial_rx_in1                  (pcie1_rx[1]),
        .hip_hip_serial_rx_in2                  (pcie1_rx[2]),
        .hip_hip_serial_rx_in3                  (pcie1_rx[3]),
        .hip_hip_serial_rx_in4                  (pcie1_rx[4]),
        .hip_hip_serial_rx_in5                  (pcie1_rx[5]),
        .hip_hip_serial_rx_in6                  (pcie1_rx[6]),
        .hip_hip_serial_rx_in7                  (pcie1_rx[7]),
        .hip_hip_serial_tx_out0                 (pcie1_tx[0]),
        .hip_hip_serial_tx_out1                 (pcie1_tx[1]),
        .hip_hip_serial_tx_out2                 (pcie1_tx[2]),
        .hip_hip_serial_tx_out3                 (pcie1_tx[3]),
        .hip_hip_serial_tx_out4                 (pcie1_tx[4]),
        .hip_hip_serial_tx_out5                 (pcie1_tx[5]),
        .hip_hip_serial_tx_out6                 (pcie1_tx[6]),
        .hip_hip_serial_tx_out7                 (pcie1_tx[7]),
        .core_clk_clk                           (core_clk),
        .app_reset_reset_n                      (app_reset_n),
        .design_id_external_connection_export   (DESIGN_ID),
        .abi_version_external_connection_export (ABI_VERSION),
        .heartbeat_external_connection_export   (heartbeat),
        .capabilities_external_connection_export(CAPABILITIES),
        .reset_count_external_connection_export (reset_count),
        .error_count_external_connection_export (error_count),
        .scratch_external_connection_export     (scratch)
    );

endmodule

