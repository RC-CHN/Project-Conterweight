module ddr4_sweep_bist #(
    parameter int CHANNEL_ID = 0,
    parameter int ADDRESS_WIDTH = 25,
    parameter int DATA_WIDTH = 512,
    parameter int BYTE_ENABLE_WIDTH = DATA_WIDTH / 8,
    parameter int PATTERN_COUNT = 4,
    parameter int MAX_OUTSTANDING_READS = 64
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

    output logic                         running,
    output logic [3:0]                   state_status,
    output logic [1:0]                   pattern_status,
    output logic [31:0]                  heartbeat_gray,
    output logic [31:0]                  pass_count_gray,
    output logic [31:0]                  error_count_gray,
    output logic [ADDRESS_WIDTH-1:0]     address_gray,
    output logic [ADDRESS_WIDTH-1:0]     first_error_address,
    output logic [BYTE_ENABLE_WIDTH-1:0] error_byte_mask,
    output logic [63:0]                  last_write_cycles_gray,
    output logic [63:0]                  last_read_cycles_gray
);

    localparam logic [ADDRESS_WIDTH-1:0] LAST_ADDRESS = {ADDRESS_WIDTH{1'b1}};
    localparam int OUTSTANDING_WIDTH = $clog2(MAX_OUTSTANDING_READS + 1);

    typedef enum logic [3:0] {
        ST_IDLE       = 4'd0,
        ST_WRITE      = 4'd1,
        ST_READ       = 4'd2
    } state_t;

    state_t state;
    logic [1:0] pattern;
    logic [ADDRESS_WIDTH-1:0] write_address;
    logic [ADDRESS_WIDTH-1:0] read_issue_address;
    logic [ADDRESS_WIDTH-1:0] read_response_address;
    logic [DATA_WIDTH-1:0] write_line_data;
    logic [DATA_WIDTH-1:0] expected_line_data;
    logic [OUTSTANDING_WIDTH-1:0] outstanding_reads;
    logic read_issue_done;
    logic [31:0] heartbeat;
    logic [31:0] pass_count;
    logic [31:0] error_count;
    logic [63:0] write_phase_cycles;
    logic [63:0] read_phase_cycles;
    logic [63:0] last_write_cycles;
    logic [63:0] last_read_cycles;

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] reset_sync;
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
    wire read_accept = avm_read && !avm_waitrequest;
    wire [DATA_WIDTH-1:0] read_difference =
        avm_readdata ^ expected_line_data;

    // Arria 10 configuration initializes these registers before the EMIF user
    // clocks start.  Keeping the wide datapath off reset_n avoids turning the
    // synchronized reset release into a 512-bit high-fanout timing path.  The
    // small control synchronizer below still forces the engine back to IDLE
    // after any runtime reset, and the host pulses clear before every sweep.
    initial begin
        state = ST_IDLE;
        pattern = '0;
        write_address = '0;
        read_issue_address = '0;
        read_response_address = '0;
        write_line_data = initial_line(2'd0);
        expected_line_data = initial_line(2'd0);
        outstanding_reads = '0;
        read_issue_done = 1'b0;
        heartbeat = '0;
        pass_count = '0;
        error_count = '0;
        write_phase_cycles = '0;
        read_phase_cycles = '0;
        last_write_cycles = '0;
        last_read_cycles = '0;
        first_error_address = '0;
        error_byte_mask = '0;
        reset_sync = '0;
        enable_sync = '0;
        clear_sync = '0;
        clear_previous = 1'b0;
    end

    assign avm_address = (state == ST_READ) ? read_issue_address : write_address;
    assign avm_writedata = write_line_data;
    assign avm_byteenable = {BYTE_ENABLE_WIDTH{1'b1}};
    assign avm_write = (state == ST_WRITE);
    // Keep the command pipe full.  A response arriving while the outstanding
    // window is full makes room for a replacement command in the same cycle.
    assign avm_read = (state == ST_READ) && !read_issue_done &&
        ((outstanding_reads < MAX_OUTSTANDING_READS) || avm_readdatavalid);
    assign running = (state != ST_IDLE);
    assign state_status = state;
    assign pattern_status = pattern;
    assign heartbeat_gray = heartbeat ^ (heartbeat >> 1);
    assign pass_count_gray = pass_count ^ (pass_count >> 1);
    assign error_count_gray = error_count ^ (error_count >> 1);
    assign address_gray = ((state == ST_READ) ? read_response_address : write_address) ^
        (((state == ST_READ) ? read_response_address : write_address) >> 1);
    assign last_write_cycles_gray =
        last_write_cycles ^ (last_write_cycles >> 1);
    assign last_read_cycles_gray =
        last_read_cycles ^ (last_read_cycles >> 1);

    // Treat the Platform Designer reset as a local asynchronous control input
    // and synchronize it as data.  This avoids distributing the controller's
    // reset output as a high-fanout synchronous-reset path at 266.7 MHz.  A
    // reset suppresses enable after the short local synchronization pipeline;
    // the datapath then returns to IDLE through the ordinary clocked logic.
    always_ff @(posedge clk) begin
        reset_sync <= {reset_sync[0], reset_n};
        enable_sync <= {enable_sync[0], enable_async & reset_sync[1]};
        clear_sync <= {clear_sync[0], clear_async};
        clear_previous <= clear_sync[1];
    end

    always_ff @(posedge clk) begin
        heartbeat <= heartbeat + 1'b1;

        if (clear_event) begin
            pass_count <= '0;
            error_count <= '0;
            first_error_address <= '0;
            error_byte_mask <= '0;
            last_write_cycles <= '0;
            last_read_cycles <= '0;
        end

        if (!enable_sync[1]) begin
            state <= ST_IDLE;
            pattern <= '0;
            write_address <= '0;
            read_issue_address <= '0;
            read_response_address <= '0;
            write_line_data <= initial_line(2'd0);
            expected_line_data <= initial_line(2'd0);
            outstanding_reads <= '0;
            read_issue_done <= 1'b0;
            write_phase_cycles <= '0;
            read_phase_cycles <= '0;
        end else begin
            case (state)
                ST_IDLE: begin
                    pattern <= '0;
                    write_address <= '0;
                    read_issue_address <= '0;
                    read_response_address <= '0;
                    write_line_data <= initial_line(2'd0);
                    expected_line_data <= initial_line(2'd0);
                    outstanding_reads <= '0;
                    read_issue_done <= 1'b0;
                    write_phase_cycles <= '0;
                    read_phase_cycles <= '0;
                    state <= ST_WRITE;
                end

                ST_WRITE: begin
                    write_phase_cycles <= write_phase_cycles + 1'b1;
                    if (!avm_waitrequest) begin
                        if (write_address == LAST_ADDRESS) begin
                            read_issue_address <= '0;
                            read_response_address <= '0;
                            expected_line_data <= initial_line(pattern);
                            outstanding_reads <= '0;
                            read_issue_done <= 1'b0;
                            state <= ST_READ;
                        end else begin
                            write_address <= write_address + 1'b1;
                            write_line_data <= next_line(write_line_data, pattern);
                        end
                    end
                end

                ST_READ: begin
                    read_phase_cycles <= read_phase_cycles + 1'b1;

                    case ({read_accept, avm_readdatavalid})
                        2'b10: outstanding_reads <= outstanding_reads + 1'b1;
                        2'b01: outstanding_reads <= outstanding_reads - 1'b1;
                        default: outstanding_reads <= outstanding_reads;
                    endcase

                    if (read_accept) begin
                        if (read_issue_address == LAST_ADDRESS)
                            read_issue_done <= 1'b1;
                        else
                            read_issue_address <= read_issue_address + 1'b1;
                    end

                    if (avm_readdatavalid) begin
                        if (read_difference != '0) begin
                            if (error_count == 0)
                                first_error_address <= read_response_address;
                            if (error_count != 32'hffff_ffff)
                                error_count <= error_count + 1'b1;
                            error_byte_mask <= error_byte_mask | byte_errors(read_difference);
                        end

                        if (read_response_address == LAST_ADDRESS) begin
                            outstanding_reads <= '0;
                            read_issue_done <= 1'b0;
                            write_address <= '0;
                            if (pattern == PATTERN_COUNT - 1) begin
                                pattern <= '0;
                                pass_count <= pass_count + 1'b1;
                                write_line_data <= initial_line(2'd0);
                                last_write_cycles <= write_phase_cycles;
                                last_read_cycles <= read_phase_cycles + 1'b1;
                                write_phase_cycles <= '0;
                                read_phase_cycles <= '0;
                            end else begin
                                pattern <= pattern + 1'b1;
                                write_line_data <= initial_line(pattern + 1'b1);
                            end
                            state <= ST_WRITE;
                        end else begin
                            read_response_address <= read_response_address + 1'b1;
                            expected_line_data <= next_line(expected_line_data, pattern);
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
