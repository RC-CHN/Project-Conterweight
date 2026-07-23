module pcie_dma_top (
    input  wire       pcie1_refclk,
    input  wire       pcie1_perstn,
    input  wire [7:0] pcie1_rx,
    output wire [7:0] pcie1_tx,
    output wire [8:0] leds
);

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
        .status_perst_perst_n                   (pcie1_perstn),
        .status_leds_leds                       (leds)
    );

endmodule
