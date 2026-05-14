// =============================================================
// I2C Master Node — FSM Implementation  (fixed)
// Sends: START → ADDRESS (7-bit) → R/W → ACK → DATA (8-bit) → ACK → STOP
// =============================================================

module i2c_master (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire [6:0] addr,
    input  wire rw,
    input  wire [7:0] data_out,
    output reg [7:0] data_in,
    output reg scl,
    inout  wire sda,
    output reg busy,
    output reg done
);

    reg sda_out, sda_en;
    assign sda = sda_en ? sda_out : 1'bz;

    reg [1:0] clk_div;
    reg scl_en;

    always @(posedge clk or posedge rst)
        if (rst) clk_div <= 0; else clk_div <= clk_div + 1;

    always @(posedge clk or posedge rst) begin
        if (rst) scl <= 1;
        else if (scl_en) scl <= (clk_div == 2'b11) ? 1 :
                                (clk_div == 2'b01) ? 0 : scl;
        else scl <= 1;
    end

    wire shift_tick  = (clk_div == 2'b01);
    wire sample_tick = (clk_div == 2'b11);

    localparam [3:0]
    IDLE=4'd0, S_START=4'd1, ADDR=4'd2, RW_BIT=4'd3, ACK1=4'd4,
    DATA=4'd5, ACK2=4'd6,   S_STOP=4'd7, DONE=4'd8;

    reg [3:0] state;
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state<=IDLE; scl_en<=0; sda_en<=1; sda_out<=1; busy<=0; done<=0;
        end else begin
            done <= 0;
            case (state)
                IDLE: begin
                    scl_en<=0; sda_en<=1; sda_out<=1; busy<=0;
                    if (start) begin busy<=1; state<=S_START; end
                end
                S_START: begin
                    sda_en<=1; sda_out<=0; scl_en<=1; bit_cnt<=6; state<=ADDR;
                end
                ADDR: begin
                    if (shift_tick) begin
                        sda_en<=1; sda_out<=addr[bit_cnt];
                        if (bit_cnt==0) state<=RW_BIT; else bit_cnt<=bit_cnt-1;
                    end
                end
                RW_BIT: begin
                    if (shift_tick) begin sda_en<=1; sda_out<=rw; state<=ACK1; end
                end
                ACK1: begin
                    if (shift_tick) sda_en<=0; //simplification - ignoring nack/ack.
                    if (sample_tick) begin bit_cnt<=7; shift_reg<=data_out; state<=DATA; end
                end
                DATA: begin
                    if (rw==0) begin
                        if (shift_tick) begin
                            sda_en<=1; sda_out<=shift_reg[bit_cnt];
                            if (bit_cnt==0) state<=ACK2; else bit_cnt<=bit_cnt-1;
                        end
                    end else begin
                        sda_en<=0;
                        if (sample_tick) begin
                            data_in[bit_cnt]<=sda;
                            if (bit_cnt==0) state<=ACK2; else bit_cnt<=bit_cnt-1;
                        end
                    end
                end
                ACK2: begin
                    if (shift_tick) begin
                        sda_en  <= (rw==1) ? 1'b1 : 1'b0;
                        sda_out <= 1;
                        state <= S_STOP;
                    end
                end
                S_STOP: begin
                    if (shift_tick) begin scl_en<=0; sda_en<=1; sda_out<=0; end
                    if (sample_tick) begin sda_out<=1; state<=DONE; end
                end
                DONE: begin done<=1; busy<=0; state<=IDLE; end
            endcase
        end
    end
endmodule
