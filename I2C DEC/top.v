// =============================================================
// top.v — Basys 3 I2C Loopback Demo
// Master and Slave instantiated on the same FPGA.
//
// Board Resources:
//   SW[6:0]   — slave address (sent by master, matched by slave)
//   SW[15:8]  — 8-bit write data
//   SW[7]     — R/W select  (0=Write, 1=Read)
//   BTNC      — start transaction (debounced)
//   BTNU      — reset
//
//   7-seg display:
//     Digit 3 (leftmost) : TX byte (what master sends / slave tx_data)
//     Digit 2            : RX byte (what slave received  / master read)
//     Digit 1            : slave address (SW[6:0])
//     Digit 0 (rightmost): status nibble
//                           bit3 = busy
//                           bit2 = done (latched)
//                           bit1 = ack_error
//                           bit0 = rx_valid (latched)
// =============================================================

module top (
    input  wire clk, // 100 MHz on Basys 3
    input  wire [15:0] sw,
    input  wire btnc, // start
    input  wire btnu, // reset
    output wire [15:0] led,
    output wire [6:0] seg, // 7-seg cathodes (active-low)
    output wire [3:0] an // digit anodes (active-low)
);

    // -------------------------------------------------------
    // Button debouncer for BTNC (start) and BTNU (rst)
    // -------------------------------------------------------
    wire start_pulse, rst;
    debounce db_start (.clk(clk), .btn_in(btnc), .pulse(start_pulse));
    debounce db_rst   (.clk(clk), .btn_in(btnu), .pulse_raw(rst));

    // -------------------------------------------------------
    // I2C bus wires (internal — no external pins needed)
    // -------------------------------------------------------
    wire sda, scl;

    // -------------------------------------------------------
    // Input mapping
    // -------------------------------------------------------
    wire [6:0] addr = sw[6:0];
    wire rw = sw[7];
    wire [7:0] tx_byte = sw[15:8];  // written by master / served by slave

    // -------------------------------------------------------
    // Master instance
    // -------------------------------------------------------
    wire [7:0] master_data_in; // data master read from slave
    wire busy, done;
    wire ack_error;

    i2c_master master (
        .clk (clk),
        .rst (rst),
        .start (start_pulse),
        .addr (addr),
        .rw (rw),
        .data_out (tx_byte), // master sends this on write
        .data_in  (master_data_in),
        .scl (scl),
        .sda (sda),
        .busy (busy),
        .done (done)
    );

    // -------------------------------------------------------
    // Slave instance — same address space as master target
    // -------------------------------------------------------
    wire [7:0] slave_rx;
    wire rx_valid, addressed;

    i2c_slave slave0 (
        .clk      (clk),
        .rst      (rst),
        .my_addr  (addr),         // slave listens on same addr as switches
        .scl      (scl),
        .sda      (sda),
        .rx_data  (slave_rx),
        .tx_data  (tx_byte),      // slave sends this on read
        .rx_valid (rx_valid),
        .addressed(addressed)
    );

    // -------------------------------------------------------
    // Latch done / rx_valid / ack_error until next start
    // -------------------------------------------------------
    reg done_lat, rxv_lat, ack_lat;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            done_lat <= 0; rxv_lat <= 0; ack_lat <= 0;
        end else if (start_pulse) begin
            done_lat <= 0; rxv_lat <= 0; ack_lat <= 0;
        end else begin
            if (done) done_lat <= 1;
            if (rx_valid) rxv_lat <= 1;
            if (ack_error)ack_lat <= 1;
        end
    end

    // -------------------------------------------------------
    // LED mapping
    // -------------------------------------------------------
    assign led[0]  = busy;
    assign led[1]  = done_lat;
    assign led[2]  = ack_lat;
    assign led[3]  = rxv_lat;
    assign led[4]  = addressed;
    assign led[14:5] = 0;

    // -------------------------------------------------------
    // 7-segment display data

    //seven segment display shows two hex values: what master sends (TX) and what slave receives (RX).
    // it show four nibbles (4bits each). so a total of 16 bits. 
    // if write(0) : master sends data to slave. so left_byte is tx_byte and right_byte is slave_rx.
    // if read(1) : master reads data from slave. so left_byte is master_data_in and right_byte is tx_byte (which slave serves).

    wire [7:0] left_byte  = rw ? master_data_in : tx_byte;
    wire [7:0] right_byte = rw ? tx_byte : slave_rx;

    wire [3:0] nib3 = left_byte[7:4];
    wire [3:0] nib2 = left_byte[3:0];
    wire [3:0] nib1 = right_byte[7:4];
    wire [3:0] nib0 = right_byte[3:0];

    seg7_mux display (
        .clk (clk),
        .d3 (nib3), .d2(nib2), .d1(nib1), .d0(nib0),
        .seg (seg),
        .an (an)
    );

endmodule


// =============================================================
// debounce — 10 ms debounce, outputs a 1-cycle pulse on release
// =============================================================
module debounce (
    input  wire clk,
    input  wire btn_in,
    output wire pulse,
    output wire pulse_raw
);
    // 100 MHz → 10 ms = 1_000_000 cycles
    localparam DCOUNT = 20'd999_999;
    reg [19:0] cnt;
    reg        stable, prev;

    always @(posedge clk) begin
        if (btn_in != stable) begin
            cnt <= 0;
        end else if (cnt < DCOUNT) begin
            cnt <= cnt + 1;
        end
        if (cnt == DCOUNT) stable <= btn_in;
        prev <= stable;
    end

    assign pulse = (stable && !prev);   // rising edge of debounced btn
    assign pulse_raw =  stable;
endmodule


// =============================================================
// hex_to_seg — convert 4-bit nibble to 7-segment (active-low)
// Segments: seg[6:0] = {g,f,e,d,c,b,a}
// =============================================================
module hex_to_seg (
    input  wire [3:0] nibble,
    output reg  [6:0] seg
);
    always @(*) begin
        case (nibble)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            4'hF: seg = 7'b0001110;
            default: seg = 7'b1111111;
        endcase
    end
endmodule


// =============================================================
// seg7_mux — time-multiplexed 4-digit 7-segment controller
// Refresh rate: 100 MHz / 2^18 ≈ 381 Hz per digit (1.5 kHz total)
// =============================================================

// the display cannot show all 16 bits at once, so we use a mux to show 4 bits at a time.
// the display has 4 digits, so we can show 4 nibbles (4 bits each) by rapidly switching between them.
// the refresh rate is fast enough that it appears to be showing all digits at once.

module seg7_mux (
    input  wire clk,
    input  wire [3:0] d3, d2, d1, d0,
    output wire [6:0] seg,
    output reg  [3:0] an
);
    reg [17:0] refresh;
    always @(posedge clk) refresh <= refresh + 1;

    wire [1:0] sel = refresh[17:16];

    reg [3:0] active_nibble;
    always @(*) begin
        case (sel)
            2'b00: begin an = 4'b1110; active_nibble = d0; end
            2'b01: begin an = 4'b1101; active_nibble = d1; end
            2'b10: begin an = 4'b1011; active_nibble = d2; end
            2'b11: begin an = 4'b0111; active_nibble = d3; end
        endcase
    end

    hex_to_seg h2s (.nibble(active_nibble), .seg(seg));

endmodule


// test 


// set: SW[15:8] = 10110101, SW[7] = 0, SW[6:0] = 0101010 (data to send) | B | 5 | B | 5 |
//                                                               TX byte  RX byte


//SW[6:0]0101010 (same address)Address = 0x2A  SW[7]UP (1)Read mode SW[15:8]11001010 (0xCA) Data slave will serve | C | A | C | A |
//                                                                                                              master_data_in   tx_byte

