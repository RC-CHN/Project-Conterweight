module dma_status_regs (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [2:0]  avs_address,
    input  logic        avs_read,
    input  logic        avs_write,
    input  logic [31:0] avs_writedata,
    input  logic [3:0]  avs_byteenable,
    output logic [31:0] avs_readdata,

    input  logic        perst_n_async,
    output logic [8:0]  leds_export
);

    localparam logic [31:0] DESIGN_ID    = 32'h4344_4d41; // "CDMA"
    localparam logic [31:0] ABI_VERSION  = 32'h0001_0000;
    localparam logic [31:0] CAPABILITIES = 32'h0014_000f;

    logic [31:0] heartbeat;
    logic [31:0] reset_count;
    logic [31:0] error_count;
    logic [31:0] scratch;
    logic        perst_meta;
    logic        perst_sync;
    logic        perst_prev;
    logic        seen_perst_deassert;

    initial begin
        heartbeat          = 32'd0;
        reset_count         = 32'd0;
        error_count         = 32'd0;
        scratch             = 32'd0;
        perst_meta          = 1'b0;
        perst_sync          = 1'b0;
        perst_prev          = 1'b0;
        seen_perst_deassert = 1'b0;
    end

    /*
     * These counters intentionally retain their FPGA register values across
     * PCIe application resets. The configuration image initializes them once,
     * allowing a runtime PERST assertion to remain observable after release.
     */
    always_ff @(posedge clk) begin
        heartbeat <= heartbeat + 1'b1;

        perst_meta <= perst_n_async;
        perst_sync <= perst_meta;
        perst_prev <= perst_sync;

        if (!perst_prev && perst_sync) begin
            reset_count         <= reset_count + 1'b1;
            seen_perst_deassert <= 1'b1;
        end

        if (perst_prev && !perst_sync && seen_perst_deassert)
            error_count <= error_count + 1'b1;
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            scratch <= 32'd0;
        end else if (avs_write && avs_address == 3'd6) begin
            if (avs_byteenable[0])
                scratch[7:0] <= avs_writedata[7:0];
            if (avs_byteenable[1])
                scratch[15:8] <= avs_writedata[15:8];
            if (avs_byteenable[2])
                scratch[23:16] <= avs_writedata[23:16];
            if (avs_byteenable[3])
                scratch[31:24] <= avs_writedata[31:24];
        end
    end

    always_comb begin
        avs_readdata = 32'd0;
        if (avs_read) begin
            unique case (avs_address)
                3'd0: avs_readdata = DESIGN_ID;
                3'd1: avs_readdata = ABI_VERSION;
                3'd2: avs_readdata = heartbeat;
                3'd3: avs_readdata = CAPABILITIES;
                3'd4: avs_readdata = reset_count;
                3'd5: avs_readdata = error_count;
                3'd6: avs_readdata = scratch;
                default: avs_readdata = 32'd0;
            endcase
        end
    end

    always_comb begin
        leds_export[0]   = heartbeat[27];
        leds_export[1]   = reset_n;
        leds_export[2]   = perst_sync;
        leds_export[7:3] = scratch[4:0];
        leds_export[8]   = |error_count;
    end

endmodule

