module uart_tx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115200
)(
    input  wire clk,
    input  wire rst,
    input  wire [7:0] data_in,
    input  wire start,
    output reg  tx,
    output reg  busy
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;

    localparam IDLE  = 0;
    localparam START = 1;
    localparam DATA  = 2;
    localparam STOP  = 3;

    reg [1:0] state = IDLE;

    reg [15:0] clk_count = 0;
    reg [2:0]  bit_index = 0;
    reg [7:0]  tx_shift  = 0;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            tx    <= 1;
            busy  <= 0;
        end else begin

            case (state)

            IDLE: begin
                tx   <= 1;
                busy <= 0;

                if (start) begin
                    tx_shift <= data_in;
                    clk_count <= 0;
                    busy <= 1;
                    state <= START;
                end
            end

            START: begin
                tx <= 0;

                if (clk_count == CLKS_PER_BIT-1) begin
                    clk_count <= 0;
                    state <= DATA;
                end else begin
                    clk_count <= clk_count + 1;
                end
            end

            DATA: begin
                tx <= tx_shift[bit_index];

                if (clk_count == CLKS_PER_BIT-1) begin
                    clk_count <= 0;

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
                tx <= 1;

                if (clk_count == CLKS_PER_BIT-1) begin
                    state <= IDLE;
                    clk_count <= 0;
                end else begin
                    clk_count <= clk_count + 1;
                end
            end

            endcase
        end
    end

endmodule
