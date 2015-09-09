module cclkDetector
#(
    parameter CLK_FREQ = 50000000,
    parameter integer CTR_SIZE = $clog2(CLK_FREQ/5000)
)
(
    input clk,       ///< System clock
    input cclk,      ///< cclk input from AVR
    output reg ready ///< when 1, the AVR is ready
);


reg [CTR_SIZE-1:0] counter;

wire done;


assign done = &counter;

initial begin
    ready <= 1'b0;
    counter <= 'd0;
end

always @(posedge clk) begin
    ready <= done;
    if (!cclk) begin // Reset when CCLK goes low
        counter <= 'd0;
    end
    else if (!done) begin // CCLK high
        counter <= counter + 2'd1;
    end
end

endmodule
