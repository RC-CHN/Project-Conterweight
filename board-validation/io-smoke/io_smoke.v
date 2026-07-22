// Catapult v3 low-risk board I/O validation.
//
// The five oscillator counters are exported as Gray codes so one JTAG probe
// snapshot cannot observe a multi-bit binary carry transition. J11 is strictly
// input-only. The only user I/O outputs in this design are the nine known LEDs.

module io_smoke (
    input  wire       clk_u59,
    input  wire       clk_y3,
    input  wire       clk_y4,
    input  wire       clk_y5,
    input  wire       clk_y6,
    input  wire [2:0] gpio_j11,
    output wire [8:0] leds
);

    reg [31:0] count_u59;

    // Only a six-bit divider runs in each fast oscillator domain. Bit 5 has a
    // transition rate of input_frequency / 32 (about 20.14 MHz at 644.53125
    // MHz), which can be safely observed by the 100 MHz U59 domain.
    reg [5:0] prescale_y3;
    reg [5:0] prescale_y4;
    reg [5:0] prescale_y5;
    reg [5:0] prescale_y6;
    always @(posedge clk_y3) prescale_y3 <= prescale_y3 + 1'b1;
    always @(posedge clk_y4) prescale_y4 <= prescale_y4 + 1'b1;
    always @(posedge clk_y5) prescale_y5 <= prescale_y5 + 1'b1;
    always @(posedge clk_y6) prescale_y6 <= prescale_y6 + 1'b1;

    reg [3:0] toggle_meta;
    reg [3:0] toggle_sync;
    reg [3:0] toggle_prev;
    reg [31:0] events_y3;
    reg [31:0] events_y4;
    reg [31:0] events_y5;
    reg [31:0] events_y6;
    always @(posedge clk_u59) begin
        count_u59  <= count_u59 + 1'b1;
        toggle_meta <= {prescale_y6[5], prescale_y5[5],
                        prescale_y4[5], prescale_y3[5]};
        toggle_sync <= toggle_meta;
        toggle_prev <= toggle_sync;
        events_y3 <= events_y3 + (toggle_sync[0] ^ toggle_prev[0]);
        events_y4 <= events_y4 + (toggle_sync[1] ^ toggle_prev[1]);
        events_y5 <= events_y5 + (toggle_sync[2] ^ toggle_prev[2]);
        events_y6 <= events_y6 + (toggle_sync[3] ^ toggle_prev[3]);
    end

    wire [31:0] gray_u59 = count_u59 ^ (count_u59 >> 1);
    wire [31:0] gray_y3  = events_y3 ^ (events_y3 >> 1);
    wire [31:0] gray_y4  = events_y4 ^ (events_y4 >> 1);
    wire [31:0] gray_y5  = events_y5 ^ (events_y5 >> 1);
    wire [31:0] gray_y6  = events_y6 ^ (events_y6 >> 1);

    reg [2:0] gpio_meta;
    reg [2:0] gpio_sync;
    always @(posedge clk_u59) begin
        gpio_meta <= gpio_j11;
        gpio_sync <= gpio_meta;
    end

    // Advance the automatic LED walk every 250 ms from the 100 MHz reference.
    reg [24:0] led_divider;
    reg [3:0]  led_index;
    always @(posedge clk_u59) begin
        if (led_divider == 25_000_000 - 1) begin
            led_divider <= 0;
            if (led_index == 8)
                led_index <= 0;
            else
                led_index <= led_index + 1'b1;
        end else begin
            led_divider <= led_divider + 1'b1;
        end
    end

    // source_control[8:0]  = exact manual LED pin values
    // source_control[9]    = manual enable
    // source_control[10]   = invert the automatic one-hot walk
    // source_control[15:11] reserved
    wire [15:0] source_control;
    wire [8:0] auto_led = (9'b1 << led_index) ^ {9{source_control[10]}};
    wire [8:0] led_drive = source_control[9] ? source_control[8:0] : auto_led;
    assign leds = led_drive;

    // Probe layout, least-significant field first:
    //   [31:0]    U59 Gray counter
    //   [63:32]   Y3 divided-edge Gray counter (multiply delta by 32)
    //   [95:64]   Y4 divided-edge Gray counter (multiply delta by 32)
    //   [127:96]  Y5 divided-edge Gray counter (multiply delta by 32)
    //   [159:128] Y6 divided-edge Gray counter (multiply delta by 32)
    //   [162:160] synchronized J11 inputs
    //   [171:163] LED pin values
    //   [175:172] automatic LED index
    //   [191:176] JTAG source/control readback
    wire [191:0] probe_data = {
        source_control,
        led_index,
        led_drive,
        gpio_sync,
        gray_y6,
        gray_y5,
        gray_y4,
        gray_y3,
        gray_u59
    };

    altsource_probe #(
        .sld_auto_instance_index("YES"),
        .sld_instance_index(0),
        .instance_id("IOV1"),
        .probe_width(192),
        .source_width(16),
        .source_initial_value("0000"),
        .enable_metastability("YES")
    ) io_source_probe (
        .probe(probe_data),
        .source(source_control),
        .source_clk(clk_u59),
        .source_ena(1'b1)
    );

    initial begin
        count_u59  = 0;
        prescale_y3 = 0;
        prescale_y4 = 0;
        prescale_y5 = 0;
        prescale_y6 = 0;
        toggle_meta = 0;
        toggle_sync = 0;
        toggle_prev = 0;
        events_y3   = 0;
        events_y4   = 0;
        events_y5   = 0;
        events_y6   = 0;
        gpio_meta  = 0;
        gpio_sync  = 0;
        led_divider = 0;
        led_index   = 0;
    end

endmodule
