# I2C Loopback Demo — Basys 3

A simple I2C demo where a master and a slave talk to each other **on the same FPGA**. No external wiring needed. You set the address and data using the switches, press a button, and watch the result on the 7-segment display and LEDs.

---

## Files

| File | What it is |
|---|---|
| `top.v` | Top-level module — wires everything together |
| `masternode.v` | I2C master (FSM) |
| `slaveNode.v` | I2C slave (FSM) |
| `basys3.xdc` | Pin constraints for the Basys 3 board |

---

## How the Switches Work

| Switch(es) | Purpose |
|---|---|
| `SW[6:0]` | 7-bit slave address |
| `SW[7]` | Mode — **0 = Write**, **1 = Read** |
| `SW[15:8]` | 8-bit data byte |

> In **Write** mode, `SW[15:8]` is the data the master sends to the slave.  
> In **Read** mode, `SW[15:8]` is the data the slave will serve back to the master.

---

## Buttons

| Button | Action |
|---|---|
| `BTNC` (center) | Start a transaction |
| `BTNU` (up) | Reset everything |

---

## What the 7-Segment Display Shows

The display shows **4 hex digits** (one nibble each):

```
[ TX high ] [ TX low ] [ RX high ] [ RX low ]
     Digit 3      Digit 2      Digit 1      Digit 0
```

- **Write mode:** TX = what the master sent, RX = what the slave received.
- **Read mode:** TX = what the master read back, RX = what the slave served.

---

## What the LEDs Show

| LED | Meaning |
|---|---|
| `LED[0]` | Busy — transaction in progress |
| `LED[1]` | Done — transaction completed |
| `LED[2]` | ACK error |
| `LED[3]` | RX valid — slave received data |
| `LED[4]` | Addressed — slave recognized its address |

---

## Quick Test Examples

**Write test**
- `SW[15:8]` = `10110101` (0xB5) — data to send
- `SW[7]` = `0` (Write)
- `SW[6:0]` = `0101010` (address 0x2A)
- Press `BTNC`
- Display should show: `B 5 B 5`

**Read test**
- `SW[15:8]` = `11001010` (0xCA) — data slave will serve
- `SW[7]` = `1` (Read)
- `SW[6:0]` = `0101010` (address 0x2A)
- Press `BTNC`
- Display should show: `C A C A`

---

## How It Works (Brief)

The master and slave share internal `SDA` and `SCL` wires — there are no external I/O pins for the I2C bus. Both are FSM-based and run off the 100 MHz board clock.

**Write transaction flow:**
`START → Address (7-bit) → R/W bit → ACK → Data (8-bit) → ACK → STOP`

**Read transaction flow:**
Same address phase, but after ACK the slave drives the data byte instead of the master.

The `debounce` module filters button presses to a clean single-cycle pulse (~10 ms settling time). The 7-segment display uses time-multiplexing to show all four digits at ~381 Hz refresh per digit.

---

## Target Board

**Digilent Basys 3** — Xilinx Artix-7 (`xc7a35tcpg236-1`), 100 MHz clock.
