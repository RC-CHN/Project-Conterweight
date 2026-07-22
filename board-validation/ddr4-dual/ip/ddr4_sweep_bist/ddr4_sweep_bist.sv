module ddr4_sweep_bist #(
    parameter int CHANNEL_ID = 0,
    parameter int ADDRESS_WIDTH = 25,
    parameter int DATA_WIDTH = 512,
    parameter int BYTE_ENABLE_WIDTH = DATA_WIDTH / 8,
    parameter int PATTERN_COUNT = 4
) (
    input  logic                         clk,
    input  logic                         reset_n,

    input  logic                         enable_async,
    input  logic                         clear_async,

    output logic [ADDRESS_WIDTH-1:0]     avm_address,
    output logic                         avm_read,
    output logic                         avm_write,
    output logic [DATA_WIDTH-1:0]        avm_writedata,
    input  logic [DATA_WIDTH-1:0]        avm_readdata,
    input  logic                         avm_waitrequest,
    input  logic                         avm_readdatavalid,
    output logic [BYTE_ENABLE_WIDTH-1:0] avm_byteenable,
    output logic [6:0]                   avm_burstcount,

    output logic                         running,
    output logic [3:0]                   state_status,
    output logic [1:0]                   pattern_status,
    output logic [31:0]                  heartbeat_gray,
    output logic [31:0]                  pass_count_gray,
    output logic [31:0]                  error_count_gray,
    output logic [ADDRESS_WIDTH-1:0]     address_gray,
    output logic [ADDRESS_WIDTH-1:0]     first_error_address,
    output logic [BYTE_ENABLE_WIDTH-1:0] error_byte_mask
);

    localparam logic [ADDRESS_WIDTH-1:0] LAST_ADDRESS = {ADDRESS_WIDTH{1'b1}};

    typedef enum logic [3:0] {
        ST_IDLE       = 4'd0,
        ST_WRITE      = 4'd1,
        ST_READ_CMD   = 4'd2,
        ST_READ_WAIT  = 4'd3
    } state_t;

    state_t state;
    logic [1:0] pattern;
    logic [ADDRESS_WIDTH-1:0] word_address;
    logic [DATA_WIDTH-1:0] line_data;
    logic [31:0] heartbeat;
    logic [31:0] pass_count;
    logic [31:0] error_count;

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] enable_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] clear_sync;
    logic clear_previous;

    function automatic logic [31:0] lfsr_next(input logic [31:0] value);
        lfsr_next = {value[30:0], value[31] ^ value[21] ^ value[1] ^ value[0]};
    endfunction

    function automatic logic [DATA_WIDTH-1:0] initial_line(input logic [1:0] selected_pattern);
        logic [DATA_WIDTH-1:0] value;
        logic [31:0] lane_seed;
        int lane;
        begin
            value = '0;
            case (selected_pattern)
                2'd0, 2'd1: begin
                    for (lane = 0; lane < DATA_WIDTH / 32; lane = lane + 1) begin
                        lane_seed = 32'h6d5a_1234 ^ (32'h1f12_3bb5 * lane)
                            ^ (32'h9e37_79b9 * CHANNEL_ID);
                        if (selected_pattern == 2'd1)
                            lane_seed = ~lane_seed;
                        if (lane_seed == 0)
                            lane_seed = 32'h1;
                        value[lane * 32 +: 32] = lane_seed;
                    end
                end
                2'd2: value[0] = 1'b1;
                default: value = {DATA_WIDTH{1'b1}} ^ {{(DATA_WIDTH-1){1'b0}}, 1'b1};
            endcase
            initial_line = value;
        end
    endfunction

    function automatic logic [DATA_WIDTH-1:0] next_line(
        input logic [DATA_WIDTH-1:0] current,
        input logic [1:0] selected_pattern
    );
        logic [DATA_WIDTH-1:0] value;
        int lane;
        begin
            value = current;
            case (selected_pattern)
                2'd0, 2'd1: begin
                    for (lane = 0; lane < DATA_WIDTH / 32; lane = lane + 1)
                        value[lane * 32 +: 32] = lfsr_next(current[lane * 32 +: 32]);
                end
                2'd2, 2'd3: value = {current[DATA_WIDTH-2:0], current[DATA_WIDTH-1]};
                default: value = current;
            endcase
            next_line = value;
        end
    endfunction

    function automatic logic [BYTE_ENABLE_WIDTH-1:0] byte_errors(
        input logic [DATA_WIDTH-1:0] difference
    );
        logic [BYTE_ENABLE_WIDTH-1:0] mask;
        int byte_index;
        begin
            for (byte_index = 0; byte_index < BYTE_ENABLE_WIDTH; byte_index = byte_index + 1)
                mask[byte_index] = |difference[byte_index * 8 +: 8];
            byte_errors = mask;
        end
    endfunction

    wire clear_event = clear_sync[1] & ~clear_previous;
    wire [DATA_WIDTH-1:0] read_difference = avm_readdata ^ line_data;

    assign avm_address = word_address;
    assign avm_writedata = line_data;
    assign avm_byteenable = {BYTE_ENABLE_WIDTH{1'b1}};
    assign avm_burstcount = 7'd1;
    assign avm_write = (state == ST_WRITE);
    assign avm_read = (state == ST_READ_CMD);
    assign running = (state != ST_IDLE);
    assign state_status = state;
    assign pattern_status = pattern;
    assign heartbeat_gray = heartbeat ^ (heartbeat >> 1);
    assign pass_count_gray = pass_count ^ (pass_count >> 1);
    assign error_count_gray = error_count ^ (error_count >> 1);
    assign address_gray = word_address ^ (word_address >> 1);

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            enable_sync <= '0;
            clear_sync <= '0;
            clear_previous <= 1'b0;
        end else begin
            enable_sync <= {enable_sync[0], enable_async};
            clear_sync <= {clear_sync[0], clear_async};
            clear_previous <= clear_sync[1];
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= ST_IDLE;
            pattern <= '0;
            word_address <= '0;
            line_data <= '0;
            heartbeat <= '0;
            pass_count <= '0;
            error_count <= '0;
            first_error_address <= '0;
            error_byte_mask <= '0;
        end else begin
            heartbeat <= heartbeat + 1'b1;

            if (clear_event) begin
                pass_count <= '0;
                error_count <= '0;
                first_error_address <= '0;
                error_byte_mask <= '0;
            end

            if (!enable_sync[1]) begin
                state <= ST_IDLE;
                pattern <= '0;
                word_address <= '0;
                line_data <= initial_line(2'd0);
            end else begin
                case (state)
                    ST_IDLE: begin
                        pattern <= '0;
                        word_address <= '0;
                        line_data <= initial_line(2'd0);
                        state <= ST_WRITE;
                    end

                    ST_WRITE: begin
                        if (!avm_waitrequest) begin
                            if (word_address == LAST_ADDRESS) begin
                                word_address <= '0;
                                line_data <= initial_line(pattern);
                                state <= ST_READ_CMD;
                            end else begin
                                word_address <= word_address + 1'b1;
                                line_data <= next_line(line_data, pattern);
                            end
                        end
                    end

                    ST_READ_CMD: begin
                        if (!avm_waitrequest)
                            state <= ST_READ_WAIT;
                    end

                    ST_READ_WAIT: begin
                        if (avm_readdatavalid) begin
                            if (read_difference != '0) begin
                                if (error_count == 0)
                                    first_error_address <= word_address;
                                if (error_count != 32'hffff_ffff)
                                    error_count <= error_count + 1'b1;
                                error_byte_mask <= error_byte_mask | byte_errors(read_difference);
                            end

                            if (word_address == LAST_ADDRESS) begin
                                word_address <= '0;
                                if (pattern == PATTERN_COUNT - 1) begin
                                    pattern <= '0;
                                    pass_count <= pass_count + 1'b1;
                                    line_data <= initial_line(2'd0);
                                end else begin
                                    pattern <= pattern + 1'b1;
                                    line_data <= initial_line(pattern + 1'b1);
                                end
                                state <= ST_WRITE;
                            end else begin
                                word_address <= word_address + 1'b1;
                                line_data <= next_line(line_data, pattern);
                                state <= ST_READ_CMD;
                            end
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
