// shortest path routing algorithm of Spidergon

module router 
#(parameter 	

	`ifdef FORMAL	
		NUM_OF_NODES=8 
	`else
		NUM_OF_NODES=32
	`endif
)
(dest_node, current_node, direction);

localparam DIRECTION_WIDTH = 2;

localparam STOP = 3;
localparam ACROSS = 2;
localparam CLOCKWISE = 1;
localparam ANTI_CLOCKWISE = 0;

//input clk;
input [$clog2(NUM_OF_NODES)-1:0] dest_node, current_node;
output reg [DIRECTION_WIDTH-1:0] direction; // stop, clockwise, anti-clockwise, across

// RelAd = ((dest-current) mod (NUM_OF_NODES)) * 4
// https://en.wikipedia.org/wiki/Modulo_operation#Performance_issues
// x % 2^n == x < 0 ? x | ~(2^n - 1) : x & (2^n - 1)

wire signed [$clog2(NUM_OF_NODES)-1:0] diff;
wire [$clog2(NUM_OF_NODES)-1:0] RelAd;

assign diff = dest_node - current_node;

/* verilator lint_off WIDTH */
assign RelAd = (diff < 0) ? (diff | ~(NUM_OF_NODES-1)) : (diff & (NUM_OF_NODES-1));
/* verilator lint_on WIDTH */


localparam SHIFT_BY_TWO = 2; // multiply by four
localparam NUM_OF_NODES_TIMES_THREE = 3*NUM_OF_NODES;
localparam NUM_OF_NODES_TIMES_FOUR = 4*NUM_OF_NODES;


/* verilator lint_off WIDTH */
wire [$clog2(NUM_OF_NODES)+1:0] RelAd_2 = (RelAd << SHIFT_BY_TWO);
/* verilator lint_on WIDTH */


always @(*)
begin
	// https://www.xilinx.com/support/answers/64777.html
	/*case(RelAd << SHIFT_BY_TWO) inside
	
		[0:0] : direction <= STOP;

		[NUM_OF_NODES:1] : direction <= CLOCKWISE;

		[NUM_OF_NODES_TIMES_FOUR:NUM_OF_NODES_TIMES_THREE] : direction <= ANTI_CLOCKWISE;

		default : direction <= ACROSS;

	endcase*/

	// https://www.reddit.com/r/yosys/comments/b0vaml/system_verilog_case_inside_range_expression/

	if(RelAd_2 == 0) direction = STOP;

	else if((RelAd_2 > 0) && (RelAd_2 <= NUM_OF_NODES)) direction = CLOCKWISE;

	else if((RelAd_2 >= NUM_OF_NODES_TIMES_THREE) && (RelAd_2 <= NUM_OF_NODES_TIMES_FOUR))
		direction = ANTI_CLOCKWISE;

	else direction = ACROSS;
end

endmodule