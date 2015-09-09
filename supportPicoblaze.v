
///////////////////////////////////////////////////////////////////////////
// MODULE DECLARATION
///////////////////////////////////////////////////////////////////////////

module supportPicoblaze
#(
    parameter PICO_IN_HIGH = 1,
    parameter PICO_OUT_HIGH = 1
)
(
    // INPUTS
    input clk,               ///< System Clock
    input nRst,              ///< Reset, active low
    input cclk,              ///< Configuration Clock from AVR
    input interrupt,         ///< Interrupt Picoblaze
    input sleep,             ///< Put Picoblaze to sleep
    input avrTx,             ///< UART RX from AVR
    input avrRxBusy,         ///< RX is busy (from AVR)
    input [7:0] inPort,      ///< Data to read in
    input [7:0] uartTxData,  ///< Data sent to UART (should come from outPort)
    input [1:0] uartControl, ///< UART control bits (should come from outPort)
    // OUTPUTS
    output [7:0] outPort,    ///< Data to write out
    output [7:0] portId,     ///< Port being used
    output [7:0] uartStatus, ///< UART status bits (should go to inPort)
    output [7:0] uartRxData, ///< Data received from UART (should go to inPort)
    output readStrobe,       ///< Picoblaze read strobe
    output writeStrobe,      ///< Picoblaze write strobe
    output kWriteStrobe,     ///< Picoblaze constant port write strobe
    output rst,              ///< Active high, set by nRst and cclk status
    output interruptAck,     ///< Interrupt ack'd by Picoblaze
    output avrRx             ///< UART TX from AVR
);

///////////////////////////////////////////////////////////////////////////
// SIGNAL DECLARATIONS
///////////////////////////////////////////////////////////////////////////

wire [11:0] address;
wire [17:0]	instruction;
wire avrReady; // High when AVR is ready to communicate
wire bramEnable;
wire uartRXFull;
wire uartRxDataPresent;
wire uartRxHalfFull;
wire uartRxReset;
wire uartTxDataPresent;
wire uartTxFull;
wire uartTxHalfFull;
wire uartTxReset;

reg [2:0] baudCount;
reg [1:0] baudModulate;
reg en16XBaud;
reg readFromUartRx;
reg writeToUartTx;

///////////////////////////////////////////////////////////////////////////
// SUPPORT CODE - Picoblaze & AVR Interface
///////////////////////////////////////////////////////////////////////////

assign rst = ~nRst | ~avrReady;

// Wait for AVR to finish booting before running normally
cclkDetector #(
    .CLK_FREQ(50000000)
)
cclkDetector0
(
    .clk(clk),       ///< System Clock
    .cclk(cclk),     ///< cclk input from AVR
    .ready(avrReady) ///< when 1, the AVR is ready
);

kcpsm6 #(
    .interrupt_vector(12'h000),
    .scratch_pad_memory_size(64),
    .hwbuild(8'h42)            // 42 hex is ASCII Character "B"
) processor (
    .address(address),
    .instruction(instruction),
    .bram_enable(bramEnable),
    .port_id(portId),
    .write_strobe(writeStrobe),
    .k_write_strobe(kWriteStrobe),
    .out_port(outPort),
    .read_strobe(readStrobe),
    .in_port(inPort),
    .interrupt(interrupt),
    .interrupt_ack(interruptAck),
    .reset(rst),
    .sleep(sleep),
    .clk(clk)
); 

program programRom (
    .enable(bramEnable),
    .address(address),
    .instruction(instruction),
    .clk(clk)
);

uartTx tx (
    // Inputs
    .clk(clk),                       ///< System clock
    .dataIn(uartTxData),             ///< [7:0] Data to transmit
    .write(writeToUartTx),           ///< Write strobe
    .rst(uartTxReset),               ///< Reset FIFO
    .x16BaudStrobe(en16XBaud),       ///< Strobe at 16x baud rate
    // Outputs
    .serialOut(avrRx),               ///< Serial transmit
    .dataPresent(uartTxDataPresent), ///< Data present in transmit buffer
    .halfFull(uartTxHalfFull),       ///< Transmit buffer is half full
    .full(uartTxFull)                ///< Transmit buffer is full
);

uartRx rx (
    .clk(clk),                       ///< System clock
    .rst(uartRxReset),               ///< Reset FIFO
    .x16BaudStrobe(en16XBaud),       ///< Strobe at 16x baud rate
    .read(readFromUartRx),           ///< Read strobe for buffer
    .serialIn(avrTx),                ///< Serial Receive
    .dataOut(uartRxData),            ///< [7:0] Data from receive buffer
    .dataPresent(uartRxDataPresent), ///< Receive buffer not empty
    .halfFull(uartRxHalfFull),       ///< Receive buffer half full
    .full(uartRXFull)                ///< Receive buffer full
);


// Set serial rate at 500000 with pulse at 8MHz. 50Mhz / 8 MHz = 6.25, so pulse at rate
// 6...6...6...7 clocks.
always @ (posedge clk )
begin
    if (rst) begin
        baudCount    <= 'd0;
        baudModulate <= 'd0;
        en16XBaud    <= 1'b0;
    end
    else begin
        if (baudCount == 3'd0) begin // counts 6 states including zero
            if (baudModulate == 2'b11) begin
                baudCount <= 3'd6;
            end
            else begin
                baudCount <= 3'd5;
            end
            baudModulate <= baudModulate + 2'd1;
            en16XBaud <= 1'b1;                 // single cycle enable pulse
        end
        else begin
            baudCount <= baudCount - 3'd1;
            en16XBaud <= 1'b0;
        end
    end
end

always @(posedge clk)
begin
    readFromUartRx <= readStrobe  && (portId[PICO_IN_HIGH:0]  ==  'd1);
    writeToUartTx  <= writeStrobe && (portId[PICO_OUT_HIGH:0] ==  'd0);
end

assign uartStatus[7] = 1'b0;
assign uartStatus[6] = avrRxBusy;
assign uartStatus[5] = uartRXFull;
assign uartStatus[4] = uartRxHalfFull;
assign uartStatus[3] = uartRxDataPresent;
assign uartStatus[2] = uartTxFull; 
assign uartStatus[1] = uartTxHalfFull;
assign uartStatus[0] = uartTxDataPresent;

assign uartTxReset = uartControl[0];
assign uartRxReset = uartControl[1];

endmodule
