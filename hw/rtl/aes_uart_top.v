`timescale 1ns / 1ps

module aes_uart_top #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115200
)(
    input  wire clk,
    input  wire rst,
    input  wire uart_rx,
    output wire uart_tx
);

    // ================= UART =================
    wire [7:0] rx_data;
    wire       rx_valid;
    

    reg  [7:0] tx_data;
    reg        tx_start;
    reg [7:0] msg_data;
    reg [7:0] msg_index;
    wire       tx_busy;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) RX (
        .clk(clk), 
        .rst(rst), 
        .rx(uart_rx),
        .data_out(rx_data), 
        .data_valid(rx_valid)
    );

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) TX (
        .clk(clk), 
        .rst(rst),
        .data_in(tx_data), 
        .start(tx_start),
        .tx(uart_tx), 
        .busy(tx_busy)
    );

    // ================= AES =================
    reg         aes_start;
    reg  [127:0] aes_din;
    wire        aes_done;
    wire [127:0] aes_ct;
    wire [127:0] aes_pt_back;

    aes128_top AES (
        .clk(clk),
        .rst(rst),
        .start(aes_start),
        .block_in(aes_din),
        .block_out_enc(aes_ct), 
        .block_out_dec(aes_pt_back),
        .done(aes_done)
    );
    
    // ================= HEX UTILS =================
    function [3:0] hex_to_nibble;
        input [7:0] c;
        begin
            case (c)
                "0": hex_to_nibble=4'h0; 
                "1": hex_to_nibble=4'h1;
                "2": hex_to_nibble=4'h2; 
                "3": hex_to_nibble=4'h3;
                "4": hex_to_nibble=4'h4; 
                "5": hex_to_nibble=4'h5;
                "6": hex_to_nibble=4'h6; 
                "7": hex_to_nibble=4'h7;
                "8": hex_to_nibble=4'h8; 
                "9": hex_to_nibble=4'h9;
                "A","a": hex_to_nibble=4'hA;
                "B","b": hex_to_nibble=4'hB;
                "C","c": hex_to_nibble=4'hC;
                "D","d": hex_to_nibble=4'hD;
                "E","e": hex_to_nibble=4'hE;
                "F","f": hex_to_nibble=4'hF;
                default: hex_to_nibble=4'h0;
            endcase
        end
    endfunction

    function [7:0] nibble_to_hex;
        input [3:0] n;
        begin
            case (n)
                4'h0: nibble_to_hex="0"; 
                4'h1: nibble_to_hex="1";
                4'h2: nibble_to_hex="2"; 
                4'h3: nibble_to_hex="3";
                4'h4: nibble_to_hex="4"; 
                4'h5: nibble_to_hex="5";
                4'h6: nibble_to_hex="6"; 
                4'h7: nibble_to_hex="7";
                4'h8: nibble_to_hex="8"; 
                4'h9: nibble_to_hex="9";
                4'hA: nibble_to_hex="A"; 
                4'hB: nibble_to_hex="B";
                4'hC: nibble_to_hex="C"; 
                4'hD: nibble_to_hex="D";
                4'hE: nibble_to_hex="E"; 
                4'hF: nibble_to_hex="F";
            endcase
        end
    endfunction
   
    function [7:0] prompt_msg;
    input [7:0] i;
    begin
        case(i)
            8'h0: prompt_msg= "I";
            8'h1: prompt_msg= "n";
            8'h2: prompt_msg= "p";
            8'h3: prompt_msg= "u";
            8'h4: prompt_msg= "t";
            8'h5: prompt_msg= " ";
            8'h6: prompt_msg= "p";
            8'h7: prompt_msg= "l";
            8'h8: prompt_msg= "a";
            8'h9: prompt_msg= "i";
            8'hA: prompt_msg= "n";
            8'hB: prompt_msg= "t";
            8'hC: prompt_msg= "e";
            8'hD: prompt_msg= "x";
            8'hE: prompt_msg= "t";
            8'hF: prompt_msg= ":";
            default: prompt_msg = 8'h00;
        endcase
    end
endfunction



        function [7:0] result_msg;
            input [7:0] i;
            begin
                case(i)
                    8'h0: result_msg = "C";
                    8'h1: result_msg = "T";
                    8'h2: result_msg = ":";
                    default: result_msg = 8'h00;
                endcase
            end
        endfunction


    // ================= FSM =================
localparam PROMPT=0, PROMPT_WAIT=1, IDLE=2, READ=3, START=4, WAIT=5, SEND_C=6, SEND_WAIT=7, SEND_D=8, SEND_WAIT_D=9, CR=10, LF=11;

    reg [3:0] state;

    reg [127:0] in_reg;
    reg [127:0] out_reg;

    reg [5:0] nib_cnt;
    reg [5:0] tx_cnt;

    always @(posedge clk) begin
        if (rst) begin

            state <= PROMPT;
            msg_index <= 0;
            
        end else begin

            tx_start <= 0;
            aes_start <= 0;

            case (state)
            
            PROMPT: begin
                if (!tx_busy) begin
                    if (prompt_msg(msg_index) != 8'h00) begin
                        tx_data <= prompt_msg(msg_index);
                        tx_start <= 1;
                        state <= PROMPT_WAIT;
                    end else begin
                        state <= CR;
                    end
                end
            end
            
            PROMPT_WAIT: begin
                if (!tx_busy) begin   // <-- change from if(tx_busy) to if(!tx_busy)
                    msg_index <= msg_index + 1;
                    state <= PROMPT;
                end
            end

            // WAIT FOR 'D'
            IDLE: begin
                if (rx_valid && (rx_data=="D" || rx_data=="d")) begin
                    nib_cnt <= 0;
                    in_reg <= 0;
                    state <= READ;
                end
            end

            // READ 32 HEX CHARS
            READ: begin
                if (rx_valid) begin
                    in_reg <= {in_reg[123:0], hex_to_nibble(rx_data)};
                    nib_cnt <= nib_cnt + 1;

                    if (nib_cnt == 31) begin
                        aes_din <= {in_reg[123:0], hex_to_nibble(rx_data)};
                        state <= START;
                    end
                end
            end

            // START AES
            START: begin
                aes_start <= 1;
                state <= WAIT;
            end

            // WAIT DONE
            WAIT: begin
                if (aes_done) begin
                    tx_cnt <= 0;
                    msg_index <= 0;
                    state <= SEND_C;
                end
            end

            // SEND HEX (indexed, no shifting
            
   // ================= SEND_C =================
        SEND_C: begin
            if (!tx_busy) begin
                if (msg_index < 15) begin
                    // Send "HERE IS THE CT:"
                    case(msg_index)
                        0: tx_data <= "H"; 1: tx_data <= "E"; 2: tx_data <= "R";
                        3: tx_data <= "E"; 4: tx_data <= " "; 5: tx_data <= "I";
                        6: tx_data <= "S"; 7: tx_data <= " "; 8: tx_data <= "T";
                        9: tx_data <= "H"; 10: tx_data <= "E"; 11: tx_data <= " ";
                        12: tx_data <= "C"; 13: tx_data <= "T"; 14: tx_data <= ":";
                    endcase
                    tx_start <= 1;             // pulse start
                    msg_index <= msg_index + 1;
                end else if (tx_cnt < 32) begin
                    // Send ciphertext nibbles
                    tx_data <= nibble_to_hex(aes_ct[127 - (tx_cnt*4) -: 4]);
                    tx_start <= 1;
                end
                state <= SEND_WAIT;
            end else begin
                tx_start <= 0; // ensure single-cycle pulse
            end
        end
        
        SEND_WAIT: begin
            if (!tx_busy) begin
                tx_start <= 0; // clear pulse after TX accepted
                if (msg_index >= 15) begin
                    if (tx_cnt == 31) begin
                        tx_cnt <= 0;
                        msg_index <= 0;
                        state <= SEND_D;  // move to decrypted output
                    end else begin
                        tx_cnt <= tx_cnt + 1;
                        state <= SEND_C;  // send next nibble
                    end
                end else begin
                    state <= SEND_C;      // continue sending message bytes
                end
            end
        end
        
        // ================= SEND_D =================
        SEND_D: begin
            if (!tx_busy) begin
                if (msg_index < 2) begin
                    // Send "D:"
                    case(msg_index)
                        0: tx_data <= "D";
                        1: tx_data <= ":";
                    endcase
                    tx_start <= 1;
                    msg_index <= msg_index + 1;
                end else if (tx_cnt < 32) begin
                    // Send decrypted nibbles
                    tx_data <= nibble_to_hex(aes_pt_back[127 - (tx_cnt*4) -: 4]);
                    tx_start <= 1;
                end
                state <= SEND_WAIT_D;
            end else begin
                tx_start <= 0;
            end
        end
        
        SEND_WAIT_D: begin
            if (!tx_busy) begin
                tx_start <= 0;
                if (msg_index >= 2) begin
                    if (tx_cnt == 31) begin
                        tx_cnt <= 0;
                        msg_index <= 0;
                        state <= CR;
                    end else begin
                        tx_cnt <= tx_cnt + 1;
                        state <= SEND_D; // send next nibble
                    end
                end else begin
                    state <= SEND_D; // continue sending "D:" 
                end
            end
        end 

            CR: begin
                if (!tx_busy) begin
                    tx_data <= 8'h0D;
                    tx_start <= 1;
                    state <= LF;
                    msg_index <= 0;
                end
            end

            LF: begin
                if (!tx_busy) begin
                    tx_data <= 8'h0A;
                    tx_start <= 1;
                    state <= IDLE;
                end
            end

            endcase
        end
    end

endmodule
