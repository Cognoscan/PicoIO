

///////////////////////////////////////////////////////////////////////////
// MODULE DECLARATION
///////////////////////////////////////////////////////////////////////////

module topChip (
    // INPUTS
    // System Inputs
    input  clk,                  ///< 50MHz clock input
    input  nRst,                 ///< Input from reset button (active low)
    input  cclk,                 ///< cclk input from AVR, high when AVR is ready
    // Inputs from AVR
    input  spiSs,                ///< SPI slave select
    input  spiMosi,              ///< SPI from AVR to FPGA
    input  spiSck,               ///< SPI clock from AVR
    input  avrTx,                ///< AVR Tx => FPGA Rx
    input  avrRxBusy,            ///< AVR Rx buffer full

    // OUTPUTS
    // Outputs to AVR
    output wire spiMiso,         ///< SPI from FPGA to AVR
    output reg [3:0] spiChannel, ///< AVR ADC channel select
    output wire avrRx,           ///< AVR Rx => FPGA Tx
    // Debug Outputs
    output reg [7:0] led         ///< Outputs to the 8 onboard LEDs
    );

///////////////////////////////////////////////////////////////////////////
// SIGNAL DECLARATIONS
///////////////////////////////////////////////////////////////////////////

localparam PICO_IN_HIGH   = 1; ///< Highest bit used for Picoblaze input multiplexer
localparam PICO_OUT_HIGH  = 1; ///< Highest bit used for Picoblaze output registers
localparam PICO_KOUT_HIGH = 0; ///< Highest bit used for Picoblaze k_output registers

///////////////////////////////////////////////////////////////////////////
// SIGNAL DECLARATIONS
///////////////////////////////////////////////////////////////////////////

reg  [7:0] inPort;
reg [1:0] baudModulate;
reg [2:0] baudCount;
reg [7:0] uartTxDataIn;
reg en16XBaud;
reg readFromUartRx;
reg uartRxReset;
reg uartTxReset;
reg writeToUartTx;

wire [11:0] address;
wire [17:0]	instruction;
wire [7:0]  uartRxDataOut;
wire [7:0] outPort;
wire [7:0] portId;
wire avrReady; // High when AVR is ready to communicate
wire bramEnable;
wire interrupt;   
wire interruptAck;
wire kWriteStrobe;
wire kcpsm6Reset;
wire kcpsm6Sleep;  
wire readStrobe;
wire rst; // Reset, active high
wire uartRXFull;
wire uartRxDataPresent;
wire uartRxHalfFull;
wire uartTxDataPresent;
wire uartTxFull;
wire uartTxHalfFull;
wire writeStrobe;

///////////////////////////////////////////////////////////////////////////
// SUPPORT CODE - Picoblaze & AVR Interface
///////////////////////////////////////////////////////////////////////////

// these signals should be high-z when not used
assign spiMiso = 1'bz;
assign avrRx = 1'bz;
always @(*) begin
    spiChannel = 4'bzzzz;
end

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

assign kcpsm6Reset = rst;
assign kcpsm6Sleep = 1'b0;
assign interrupt = interruptAck;
  
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
    .reset(kcpsm6Reset),
    .sleep(kcpsm6Sleep),
    .clk(clk)
); 

program programRom (
    .enable(bramEnable),
    .address(address),
    .instruction(instruction),
    .clk(clk)
);

uart_tx6 tx (
    .data_in(uartTxDataIn),
    .en_16_x_baud(en16XBaud),
    .serial_out(avrRx),
    .buffer_write(writeToUartTx),
    .buffer_data_present(uartTxDataPresent),
    .buffer_half_full(uartTxHalfFull),
    .buffer_full(uartTxFull),
    .buffer_reset(uartTxReset),              
    .clk(clk)
);

uart_rx6 rx (
    .serial_in(avrTx),
    .en_16_x_baud(en16XBaud),
    .data_out(uartRxDataOut),
    .buffer_read(readFromUartRx),
    .buffer_data_present(uartRxDataPresent),
    .buffer_half_full(uartRxHalfFull),
    .buffer_full(uartRXFull),
    .buffer_reset(uartRxReset),              
    .clk(clk)
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

///////////////////////////////////////////////////////////////////////////
// PICOBLAZE I/O
///////////////////////////////////////////////////////////////////////////


// Input multiplexer
always @ (posedge clk)
begin
    inPort <= 'd0; // Default, to catch unset bits
    case (portId[PICO_IN_HIGH:0]) 
        // Read UART status at port address 00 hex
        'd0 : begin
            inPort[5] <= uartRXFull;
            inPort[4] <= uartRxHalfFull;
            inPort[3] <= uartRxDataPresent;
            inPort[2] <= uartTxFull; 
            inPort[1] <= uartTxHalfFull;
            inPort[0] <= uartTxDataPresent;
        end
        // Read UART_RX6 data at port address 01 hex
        // (see 'bufferRead' pulse generation below) 
        'd1 : inPort <= uartRxDataOut;
        default : inPort <= 8'd0;
    endcase

    // Input Strobes
    readFromUartRx <= readStrobe && (portId[PICO_IN_HIGH:0] == 1'b1);
end

// Output Registers
always @ (posedge clk)
begin
    if (rst) begin
        uartTxDataIn  <= 'd0;
        led           <= 'd0;
        writeToUartTx <= 1'b0;
    end
    else begin
        if (writeStrobe) begin
            case (portId[PICO_OUT_HIGH:0])
                'd0 : uartTxDataIn <= outPort;
                'd1 : led          <= outPort;
            endcase
        end

        // Output Strobes
        writeToUartTx <= writeStrobe &&  (portId[7:0] == 8'd0);
    end
end

// Constant Output Registers
always @ (posedge clk)
begin
    if (rst) begin
        uartTxReset <= 1'b1;
        uartRxReset <= 1'b1;
    end
    else begin
        if (kWriteStrobe) begin
            case (portId[PICO_KOUT_HIGH:0])
                'd0 : begin
                    uartTxReset <= outPort[0];
                    uartRxReset <= outPort[1];
                end
            endcase
        end
    end
end

///////////////////////////////////////////////////////////////////////////
// MAIN CODE HERE
///////////////////////////////////////////////////////////////////////////

endmodule
