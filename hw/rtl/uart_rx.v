module uart_rx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115200
)(
    input  wire clk,
    input  wire rst,
    input  wire rx,
    output reg  [7:0] data_out,
    output reg        data_valid
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;

    localparam IDLE  = 0;
    localparam START = 1;
    localparam DATA  = 2;
    localparam STOP  = 3;

    reg [1:0] state = IDLE;

    reg [15:0] clk_count = 0;
    reg [2:0]  bit_index = 0;
    reg [7:0]  rx_shift  = 0;

    // Synchronize RX (important for FPGA)
    reg rx_d1, rx_d2;
    always @(posedge clk) begin
        rx_d1 <= rx;
        rx_d2 <= rx_d1;
    end

    wire rx_clean = rx_d2;

    always @(posedge clk) begin
        if (rst) begin
            state      <= IDLE;
            data_valid <= 0;
            clk_count  <= 0;
            bit_index  <= 0;
        end else begin
            data_valid <= 0;

            case (state)

            IDLE: begin
                clk_count <= 0;
                bit_index <= 0;
                if (rx_clean == 0)
                    state <= START;
            end

            START: begin
                if (clk_count == (CLKS_PER_BIT/2)) begin
                    if (rx_clean == 0) begin
                        clk_count <= 0;
                        state <= DATA;
                    end else begin
                        state <= IDLE;
                    end
                end else begin
                    clk_count <= clk_count + 1;
                end
            end

            DATA: begin
                if (clk_count == CLKS_PER_BIT-1) begin
                    clk_count <= 0;

                    rx_shift[bit_index] <= rx_clean;

                    if (bit_index == 7) begin
                        bit_index <= 0;
                        state <= STOP;
                    end else begin
                        bit_index <= bit_index + 1;
                    end
                end else begin
                    clk_count <= clk_count + 1;
                end
            end

            STOP: begin
                if (clk_count == CLKS_PER_BIT-1) begin
                    data_out   <= rx_shift;
                    data_valid <= 1;
                    state      <= IDLE;
                    clk_count  <= 0;
                end else begin
                    clk_count <= clk_count + 1;
                end
            end

            endcase
        end
    end

endmodule
