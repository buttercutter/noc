// Credit: https://github.com/thomasrussellmurphy/stx_cookbook/blob/master/arbitration/arbiter.v

// Copyright 2007 Altera Corporation. All rights reserved.  
// Altera products are protected under numerous U.S. and foreign patents, 
// maskwork rights, copyrights and other intellectual property laws.  
//
// This reference design file, and your use thereof, is subject to and governed
// by the terms and conditions of the applicable Altera Reference Design 
// License Agreement (either as signed by you or found at www.altera.com).  By
// using this reference design file, you indicate your acceptance of such terms
// and conditions between you and Altera Corporation.  In the event that you do
// not agree with such terms and conditions, you may not use the reference 
// design file and please promptly destroy any copies you have made.
//
// This reference design file is being provided on an "as-is" basis and as an 
// accommodation and therefore all warranties, representations or guarantees of 
// any kind (whether express, implied or statutory) including, without 
// limitation, warranties of merchantability, non-infringement, or fitness for
// a particular purpose, are specifically disclaimed.  By making this reference
// design file available, Altera expressly does not recommend, suggest or 
// require that this reference design file be used in combination with any 
// other product not provided by Altera.
/////////////////////////////////////////////////////////////////////////////


// baeckler - 02-13-2007
//
// 'base' is a one hot signal indicating the first request
// that should be considered for a grant.  Followed by higher
// indexed requests, then wrapping around.
//

// https://www.reddit.com/r/FPGA/comments/axutbt/understanding_a_simple_roundrobin_arbiter_verilog/

module arbiter #(parameter WIDTH = 4) (clk, reset, req, grant);

input clk, reset;
input [WIDTH-1:0] req;
output [WIDTH-1:0] grant; 

// 'grant' is one-hot vector, which means only one client request is granted/given green light to proceed

// note that 'base' is one-hot vector, 
// 'base' signal helps round-robin arbiter to decide which 'req' to start servicing
reg [WIDTH-1:0] base;

wire [2*WIDTH-1:0] double_req = {req,req};
reg [2*WIDTH-1:0] double_grant;

assign grant = double_grant[WIDTH-1:0] | double_grant[2*WIDTH-1:WIDTH];


// for reducing power consumption during the time when there is no client requests 
// by preventing signals from toggling when the arbiter is not in use.

wire idle = (req == 0);

always @(posedge clk) 
begin
	if(reset || idle) double_grant <= 0;

	else double_grant <= double_req & ~(double_req - {{(WIDTH){1'b0}}, base});
end

reg [WIDTH-1:0] req_previous;
always @(posedge clk) req_previous <= req;

always @(posedge clk)
begin
	// starts round-robin arbiter with req #0 getting prioritized first
	if(reset) base <= 1;

	// 'grant' is a one-hot signal, but 'req' is not a one-hot signal
	// 'base' is a one-hot signal which rotates
	//  after the corresponding 'req' had been granted/given permission to proceed)
	//  Rotation wraps around upon reaching MSB

	else if((grant & req_previous) == grant) // this determines whether the same client request had been granted

		base <= (base[WIDTH-1]) ? 1 : (base << 1);
end

`ifdef FORMAL

initial assume(reset);
//initial assume(req == 0);  // only enable this assume() to test the cover() at line 101 properly

genvar grant_num;

generate 
	for(grant_num = 0; grant_num < WIDTH; grant_num = grant_num + 1)
		
		always @(*)	cover(first_clock_had_passed && grant[grant_num]);  // covers grants to each of the clients' request

endgenerate


always @(posedge clk) cover(!$past(reset) && (grant == 0)); // covers the ability to go to an idle state

// covers the ability to handle requests properly even with ALL requests ON
always @(posedge clk) cover((&$past(req_previous)) && (&$past(req)) && (&req) && first_clock_had_passed && $past(first_clock_had_passed) && ((grant & $past(req)) == grant)); 


reg [WIDTH-1:0] grant_previous;
always @(posedge clk) grant_previous <= grant;

always @(posedge clk) cover(grant != grant_previous); // covers the ability to switch grants to any other requests

`endif

`ifdef FORMAL

reg first_clock_had_passed;
initial first_clock_had_passed = 0;

always @(posedge clk) first_clock_had_passed <= 1;

always @(posedge clk)
begin
	if(first_clock_had_passed)
	begin
		if($past(reset) || $past(idle)) assert(grant == 0);

		else begin
			assert((grant & $past(req)) == grant); // $onehot(grant) equivalent in the case of rr arbiter

			if (|$past(req)) assert(grant != 0);
		end
	end
end

always @(posedge clk)
begin
	if(first_clock_had_passed)
	begin
		// starts round-robin arbiter with req #0 getting prioritized first
		if($past(reset)) assert(base == 1);

		// 'grant' is a one-hot signal, but 'req' is not a one-hot signal
		// 'base' is a one-hot signal which rotates
		//  after the corresponding 'req' had been granted/given permission to proceed)
		//  Rotation wraps around upon reaching MSB

		else if(($past(grant) & $past(req_previous)) == $past(grant)) // this determines whether the same client request had been granted
		begin
			assert(base == ($past(base[WIDTH-1])) ? 1 : ($past(base) << 1));
			assert(base != 0);
		end

		else assert(base != 0);
	end
end

`endif

endmodule