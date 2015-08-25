

///////////////////////////////////////////////////////////////////////////
// MODULE DECLARATION {{{
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

// }}}
///////////////////////////////////////////////////////////////////////////
// PARAMETER DECLARATIONS {{{
///////////////////////////////////////////////////////////////////////////

localparam PICO_IN_HIGH   = 1; ///< Highest bit used for Picoblaze input multiplexer
localparam PICO_OUT_HIGH  = 1; ///< Highest bit used for Picoblaze output registers
localparam PICO_KOUT_HIGH = 0; ///< Highest bit used for Picoblaze k_output registers

// }}}
///////////////////////////////////////////////////////////////////////////
// SIGNAL DECLARATIONS {{{
///////////////////////////////////////////////////////////////////////////

wire [7:0] outPort;
wire [7:0] portId;
wire [7:0] uartStatus;
wire [7:0] uartRxData;
wire readStrobe;
wire writeStrobe;
wire kWriteStrobe;
wire rst;
wire interruptAck;
wire interrupt;
wire sleep;

reg [7:0] inPort;
reg [7:0] uartTxData;
reg [1:0] uartControl;

// }}}
///////////////////////////////////////////////////////////////////////////
// SUPPORT CODE - Picoblaze & AVR Interface {{{
///////////////////////////////////////////////////////////////////////////

// these signals should be high-z when not used
assign spiMiso = 1'bz;
assign avrRx = 1'bz;
always @(*) begin
    spiChannel = 4'bzzzz;
end

assign sleep = 1'b0;
assign interrupt = interruptAck;

supportPicoblaze #(
    .PICO_IN_HIGH(PICO_IN_HIGH),
    .PICO_OUT_HIGH(PICO_OUT_HIGH)
)
supportPicoblaze0 (
    // INPUTS
    .clk(clk),                   ///< System Clock
    .nRst(nRst),                 ///< Reset, active low
    .cclk(cclk),                 ///< Configuration Clock from AVR
    .interrupt(interrupt),       ///< Interrupt Picoblaze
    .sleep(sleep),               ///< Put Picoblaze to sleep
    .avrTx(avrTx),               ///< UART RX from AVR
    .avrRxBusy(avrRxBusy),       ///< RX is busy (from AVR)
    .inPort(inPort),             ///< [7:0] Data to read in
    .uartTxData(uartTxData),     ///< [7:0] Data sent to UART (should come from outPort)
    .uartControl(uartControl),   ///< [1:0] UART control bits (should come from outPort)
    // OUTPUTS
    .outPort(outPort),           ///< [7:0] Data to write out
    .portId(portId),             ///< [7:0] Port being used
    .uartStatus(uartStatus),     ///< [7:0] UART status bits (should go to inPort)
    .uartRxData(uartRxData),     ///< [7:0] Data received from UART (should go to inPort)
    .readStrobe(readStrobe),     ///< Picoblaze read strobe
    .writeStrobe(writeStrobe),   ///< Picoblaze write strobe
    .kWriteStrobe(kWriteStrobe), ///< Picoblaze constant port write strobe
    .rst(rst),                   ///< Active high, set by nRst and cclk status
    .interruptAck(interruptAck), ///< Interrupt ack'd by Picoblaze
    .avrRx(avrRx)                ///< UART TX from AVR
);

// }}}
///////////////////////////////////////////////////////////////////////////
// PICOBLAZE I/O {{{
///////////////////////////////////////////////////////////////////////////

// Input multiplexer
always @ (posedge clk)
begin
    inPort <= 'd0; // Default, to catch unset bits
    case (portId[PICO_IN_HIGH:0]) 
        'd0 : inPort <= uartStatus; // Read UART status at port address 00 hex
        'd1 : inPort <= uartRxData; // Read UART data at port address 01 hex
        default : inPort <= 8'd0;
    endcase

    // Read strobes
    // exampleReadStrobe <= readStrobe & (portId[PICO_IN_HIGH:0] == PORT_NUM);
end

// Output Registers
always @ (posedge clk)
begin
    if (rst) begin
        uartTxData <= 'd0;
        led        <= 'd0;
    end
    else begin
        if (writeStrobe) begin
            case (portId[PICO_OUT_HIGH:0])
                'd0 : uartTxData <= outPort;
                'd1 : led        <= outPort;
            endcase
        end

        // Write strobes
        // exampleWriteStrobe <= writeStrobe & (portId[PICO_OUT_HIGH:0] == PORT_NUM);
    end
end

// Constant Output Registers
always @ (posedge clk)
begin
    if (rst) begin
        uartControl <= 'd0;
    end
    else begin
        if (kWriteStrobe) begin
            case (portId[PICO_KOUT_HIGH:0])
                'd0 : uartControl <= outPort[1:0];
            endcase
        end
    end
end

// }}}
///////////////////////////////////////////////////////////////////////////
// MAIN CODE HERE {{{
///////////////////////////////////////////////////////////////////////////

// }}}
endmodule
/* vim: set fdm=marker: */
