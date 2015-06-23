/******************************************************************************
 This Source Code Form is subject to the terms of the
 Open Hardware Description License, v. 1.0. If a copy
 of the OHDL was not distributed with this file, You
 can obtain one at http://juliusbaxter.net/ohdl/ohdl.txt

 Description:
   Single port ram:
    a) "enable" for both read & write
    b) "write 1st": written value appears on output
    c) "clear on init" feature for simulation
   Based on mor1kx_true_dpram_sclk

 Copyright (C) 2013 Stefan Kristiansson <stefan.kristiansson@saunalahti.fi>
 Copyright (C) 2015 Andrey Bacherov <avbacherov@opencores.org>

 ******************************************************************************/

module mor1kx_spram_en_w1st
#(
  parameter ADDR_WIDTH    = 32,
  parameter DATA_WIDTH    = 32,
  parameter CLEAR_ON_INIT =  0
)
(
  // clock
  input                   clk,
  // port
  input                   en,    // enable port
  input                   we,    // operation is "write"
  input  [ADDR_WIDTH-1:0] addr,
  input  [DATA_WIDTH-1:0] din,
  output [DATA_WIDTH-1:0] dout
);

  reg [DATA_WIDTH-1:0] mem[(1<<ADDR_WIDTH)-1:0];

  reg [DATA_WIDTH-1:0] rdata;

generate
if(CLEAR_ON_INIT) begin : clear_on_init
  integer idx;
  initial
    for (idx=0; idx < (1<<ADDR_WIDTH); idx=idx+1)
      mem[idx] = {DATA_WIDTH{1'b0}};
end
endgenerate

  assign dout = rdata;

  always @(posedge clk) begin
    if(en) begin
      if (we) begin
        mem[addr] <= din;
        rdata     <= din;
      end
      else begin
        rdata <= mem[addr];
      end // write / read
    end // enable
  end // @clock

endmodule // mor1kx_spram_en_w1st