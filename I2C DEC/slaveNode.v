// =============================================================
// I2C Slave Node — FSM Implementation
// =============================================================

module i2c_slave (
    input  wire       clk,
    input  wire  rst,
    input  wire [6:0] my_addr,
    input  wire scl,
    inout  wire sda,
    output reg  [7:0] rx_data,
    input  wire [7:0] tx_data,
    output reg rx_valid,
    output reg addressed
);

    reg sda_out, sda_en;
    assign sda = sda_en ? sda_out : 1'bz;

    reg scl_d, sda_d;
    always @(posedge clk) begin scl_d <= scl; sda_d <= sda; end

    wire scl_rise  = ( scl && !scl_d);
    wire scl_fall  = (!scl && scl_d);
    wire start_det = (!sda && sda_d && scl);
    wire stop_det  = ( sda && !sda_d && scl);

    localparam [3:0]
        IDLE=4'd0, GET_ADDR=4'd1, GET_RW=4'd2, SEND_ACK1=4'd3,
        GET_DATA=4'd4, SEND_DATA=4'd5, SEND_ACK2=4'd6,
        WAIT_ACK2=4'd7, DONE=4'd8;

    reg [3:0] state;
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;
    reg rw_bit;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state<=IDLE; sda_en<=0; sda_out<=1; rx_valid<=0; addressed<=0;
        end else begin
            rx_valid <= 0;

            if (stop_det) begin
                state<=IDLE; sda_en<=0; addressed<=0;
            end else begin
                case (state)

                    IDLE: begin
                        sda_en<=0; addressed<=0;
                        if (start_det) begin
                            bit_cnt<=6; shift_reg<=0; state<=GET_ADDR;
                        end
                    end

                    GET_ADDR: begin
                        if (scl_rise) begin
                            shift_reg[bit_cnt] <= sda;
                            if (bit_cnt==0) state<=GET_RW;
                            else            bit_cnt<=bit_cnt-1;
                        end
                    end

                    GET_RW: begin
                        if (scl_rise) begin rw_bit<=sda; state<=SEND_ACK1; end
                    end

                    // Pull SDA low (ACK) on SCL falling edge if address matches
                    SEND_ACK1: begin
                        if (scl_fall) begin
                            if (shift_reg[6:0]==my_addr) begin
                                addressed <= 1;
                                sda_en    <= 1;
                                sda_out   <= 0;   // ACK
                                bit_cnt   <= 7;
                                state     <= (rw_bit) ? SEND_DATA : GET_DATA;
                            end else begin
                                sda_en <= 0; state <= IDLE;  // NACK
                            end
                        end
                        if (scl_rise && addressed) sda_en <= 0; // release after ACK
                    end

                    // Write mode: slave releases bus, samples master data
                    GET_DATA: begin
                        sda_en <= 0;
                        if (scl_rise) begin
                            shift_reg[bit_cnt] <= sda;
                            if (bit_cnt==0) state<=SEND_ACK2;
                            else            bit_cnt<=bit_cnt-1;
                        end
                    end

                    // ACK the received byte, latch data
                    SEND_ACK2: begin
                        if (scl_fall) begin
                            rx_data  <= shift_reg;
                            rx_valid <= 1;
                            sda_en   <= 1;
                            sda_out  <= 0;
                        end
                        if (scl_rise) begin
                            rx_valid <= 0;
                            sda_en   <= 0;
                            state    <= DONE;
                        end
                    end

                    // Read mode: slave drives tx_data bits.
                    // Output next bit on SCL falling edge; advance index on SCL rising edge.
                    SEND_DATA: begin
                        if (scl_fall) begin
                            sda_en  <= 1;
                            sda_out <= tx_data[bit_cnt]; // present bit BEFORE SCL rises
                        end
                        if (scl_rise) begin
                            // master has sampled, safe to advance
                            if (bit_cnt==0) state<=WAIT_ACK2;
                            else            bit_cnt<=bit_cnt-1;
                        end
                    end

                    // Release SDA for master ACK/NACK
                    WAIT_ACK2: begin
                        if (scl_fall) sda_en<=0;
                        if (scl_rise) state<=DONE;
                    end

                    DONE: begin
                        sda_en<=0; addressed<=0; state<=IDLE;
                    end

                endcase
            end
        end
    end
endmodule