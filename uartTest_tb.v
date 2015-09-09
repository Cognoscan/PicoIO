module uartTest_tb ();

reg clk;
reg rst;
reg x16BaudStrobe;
reg [7:0] dataIn;
reg write;
reg read;

wire [7:0] dataOut;
wire serial;
wire rxDataPresent;
wire rxHalfFull;
wire rxFull;
wire txDataPresent;
wire txHalfFull;
wire txFull;

initial begin
    clk = 1'b0;
    rst = 1'b0;
    x16BaudStrobe = 1'b0;
    dataIn = 'd0;
    write = 1'b0;
    read = 1'b0;
end

always #1 clk = ~clk;
always begin
    #1
    @(posedge clk) x16BaudStrobe = 1'b1;
    @(posedge clk) x16BaudStrobe = 1'b0;
end

always begin
    #1
    if (!txFull) begin
        @(posedge clk) write = 1'b1;
        @(posedge clk) write = 1'b0;
        @(posedge clk) write = 1'b0;
        dataIn = dataIn + 1;
    end
end

always begin
    #1
    if (rxDataPresent) begin
        @(posedge clk) read = 1'b1;
        @(posedge clk) read = 1'b0;
        @(posedge clk) read = 1'b0;
    end
end

uartTx uutTx (
    // Inputs
    .clk(clk),                     ///< System clock
    .rst(rst),                     ///< Reset FIFO
    .x16BaudStrobe(x16BaudStrobe), ///< Strobe at 16x baud rate
    .dataIn(dataIn),               ///< [7:0] Data to transmit
    .write(write),                 ///< Write strobe
    // Outputs
    .serialOut(serial),            ///< Serial transmit
    .dataPresent(txDataPresent),   ///< Data present in transmit buffer
    .halfFull(txHalfFull),         ///< Transmit buffer is half full
    .full(txFull)                  ///< Transmit buffer is full
);

uartRx uutRx (
    .clk(clk),                     ///< System clock
    .rst(rst),                     ///< Reset FIFO
    .x16BaudStrobe(x16BaudStrobe), ///< Strobe at 16x baud rate
    .read(read),                   ///< Read strobe for buffer
    .serialIn(serial),             ///< Serial Receive
    .dataOut(dataOut),             ///< [7:0] Data from receive buffer
    .dataPresent(rxDataPresent),   ///< Receive buffer not empty
    .halfFull(rxHalfFull),         ///< Receive buffer half full
    .full(rxFull)                  ///< Receive buffer full
);


endmodule
