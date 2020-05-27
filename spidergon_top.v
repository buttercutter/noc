// https://www.reddit.com/r/algorithms/comments/au94ak/spidergon_networksonchips/

module spidergon_top 
#(
	`ifdef FORMAL	
		parameter NUM_OF_NODES=8, 
		parameter FLIT_DATA_WIDTH=8,
		parameter NODE_BUFFER_WIDTH=16,
	`else
		parameter NUM_OF_NODES=8,
		parameter FLIT_DATA_WIDTH=16,
		parameter NODE_BUFFER_WIDTH=32, // a single vc buffer can hold 2 flits at one time
	`endif

	parameter NUM_OF_VIRTUAL_CHANNELS=2 // 2 vc for each input ports of each node
) 
(clk, reset, data_input, data_output);


// the most significant two bits are to indicate head and/or tail flits,
// followed by dest_node and flit_data_payload
// See http://www.lisnoc.org/packets.html

// 01 = head_flit , 10 = data_flit (body_flit), 00 = tail_flit, 11 = flit_without_data_payload
localparam HEAD_FLIT = 2'b01;
localparam HEADER = 2'b11; // flit_without_data_payload
localparam BODY_FLIT = 2'b10;
localparam TAIL_FLIT = 2'b00;

localparam HEAD_TAIL = 2;
parameter DEST_NODE_WIDTH = $clog2(NUM_OF_NODES);
localparam FLIT_TOTAL_WIDTH = HEAD_TAIL+FLIT_DATA_WIDTH;

localparam DIRECTION_WIDTH = 2; // $clog2(NUM_OF_PORTS)
localparam NUM_OF_PORTS = 3; // clockwise, anti-clockwise, across

localparam STOP = 3;
localparam ACROSS = 2;
localparam CLOCKWISE = 1;
localparam ANTI_CLOCKWISE = 0;

// for user application mapping, this value must be smaller than NUM_OF_NODES
localparam NUM_OF_INPUTS = 16;


input clk, reset;
input [NUM_OF_NODES*FLIT_TOTAL_WIDTH-1:0] data_input; // for initial input data of each nodes
output signed [FLIT_DATA_WIDTH-1:0] data_output;


reg [FLIT_TOTAL_WIDTH-1:0] node_data_from_cpu [NUM_OF_NODES-1:0];
wire [FLIT_TOTAL_WIDTH-1:0] node_data_to_cpu [NUM_OF_NODES-1:0];


wire [FLIT_TOTAL_WIDTH-1:0] flit_data_input [NUM_OF_NODES-1:0][NUM_OF_PORTS-1:0];
wire [FLIT_TOTAL_WIDTH-1:0] flit_data_output [NUM_OF_NODES-1:0][NUM_OF_PORTS-1:0];

wire [NUM_OF_PORTS-1:0] flit_data_input_are_valid [NUM_OF_NODES-1:0];
wire [NUM_OF_PORTS-1:0] flit_data_output_are_valid [NUM_OF_NODES-1:0];

// is the node ready to accept new head flit
wire [NUM_OF_PORTS*NUM_OF_VIRTUAL_CHANNELS-1:0] current_node_is_ready [NUM_OF_NODES-1:0];
wire [NUM_OF_PORTS*NUM_OF_VIRTUAL_CHANNELS-1:0] adjacent_nodes_are_ready [NUM_OF_NODES-1:0];

// to control the flow, acts as traffic light for the data flits
wire [NUM_OF_PORTS*NUM_OF_VIRTUAL_CHANNELS-1:0] current_node_vc_are_full[NUM_OF_NODES-1:0];
wire [NUM_OF_PORTS*NUM_OF_VIRTUAL_CHANNELS-1:0] adjacent_node_vc_are_full[NUM_OF_NODES-1:0];


// Final result output from user application mapping
assign data_output = flit_data_output[NUM_OF_NODES-1][NUM_OF_PORTS-1][FLIT_DATA_WIDTH-1:0];


`ifdef FORMAL

initial assume(reset);

reg first_clock_had_passed;
initial first_clock_had_passed = 0;

always @(posedge clk) first_clock_had_passed <= 1;

wire [NUM_OF_NODES-1:0] packet_arrived_at_dest;

reg [NUM_OF_NODES-1:0] data_packet_contains_header;
reg [NUM_OF_NODES-1:0] destination_address_matches;

initial data_packet_contains_header = 0;
initial destination_address_matches = 0;


wire [NUM_OF_PORTS*HEAD_TAIL-1:0] input_flit_type [NUM_OF_NODES-1:0];

wire [NUM_OF_PORTS*DIRECTION_WIDTH-1:0] out_port_num [NUM_OF_NODES-1:0];

`endif

generate 
	// generates all the nodes of spidergon as well as the connecting edges between nodes

	genvar node_num;

	for(node_num = 0; node_num < NUM_OF_NODES; node_num = node_num + 1) 
	begin : NODES

		if(node_num == 0)
		begin
			assign flit_data_input[node_num][ANTI_CLOCKWISE] = flit_data_output[NUM_OF_NODES-1][CLOCKWISE];
			
			assign flit_data_input_are_valid[node_num][ANTI_CLOCKWISE] = 
				   flit_data_output_are_valid[NUM_OF_NODES-1][CLOCKWISE];

			assign adjacent_node_vc_are_full[node_num][ANTI_CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS] = 
				   current_node_vc_are_full[NUM_OF_NODES-1][CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS];

			assign adjacent_nodes_are_ready[node_num][ANTI_CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS] =
				   current_node_is_ready[NUM_OF_NODES-1][CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS];
		end			
		
		else begin
			assign flit_data_input[node_num][ANTI_CLOCKWISE] = flit_data_output[node_num-1][CLOCKWISE];
			
			assign flit_data_input_are_valid[node_num][ANTI_CLOCKWISE] = 
				   flit_data_output_are_valid[node_num-1][CLOCKWISE];

			assign adjacent_node_vc_are_full[node_num][ANTI_CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS] =
				   current_node_vc_are_full[node_num-1][CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS];

			assign adjacent_nodes_are_ready[node_num][ANTI_CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS] =
				   current_node_is_ready[node_num-1][CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS];
		end


		if(node_num == (NUM_OF_NODES-1))
		begin
			assign flit_data_input[node_num][CLOCKWISE] = flit_data_output[0][ANTI_CLOCKWISE];
			
			assign flit_data_input_are_valid[node_num][CLOCKWISE] = 
				   flit_data_output_are_valid[0][ANTI_CLOCKWISE];

			assign adjacent_node_vc_are_full[node_num][CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS] =
				   current_node_vc_are_full[0][ANTI_CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS];		

			assign adjacent_nodes_are_ready[node_num][CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS] =
				   current_node_is_ready[0][ANTI_CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS];		
		end

		else begin
			assign flit_data_input[node_num][CLOCKWISE] = flit_data_output[node_num+1][ANTI_CLOCKWISE];
			
			assign flit_data_input_are_valid[node_num][CLOCKWISE] = 
				   flit_data_output_are_valid[node_num+1][ANTI_CLOCKWISE];

			assign adjacent_node_vc_are_full[node_num][CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS] =
				   current_node_vc_are_full[node_num+1][ANTI_CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS];

			assign adjacent_nodes_are_ready[node_num][CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS] =
				   current_node_is_ready[node_num+1][ANTI_CLOCKWISE*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS];
		end


		if(node_num >= (NUM_OF_NODES>>1))
		begin
			assign flit_data_input[node_num][ACROSS] = flit_data_output[node_num-(NUM_OF_NODES>>1)][ACROSS];
			
			assign flit_data_input_are_valid[node_num][ACROSS] = 
				   flit_data_output_are_valid[node_num-(NUM_OF_NODES>>1)][ACROSS];

			assign adjacent_node_vc_are_full[node_num][ACROSS*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS] =
				   current_node_vc_are_full[node_num-(NUM_OF_NODES>>1)][ACROSS*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS];

			assign adjacent_nodes_are_ready[node_num][ACROSS*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS] =
				   current_node_is_ready[node_num-(NUM_OF_NODES>>1)][ACROSS*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS];
		end

		else begin
			assign flit_data_input[node_num][ACROSS] = flit_data_output[node_num+(NUM_OF_NODES>>1)][ACROSS];
			
			assign flit_data_input_are_valid[node_num][ACROSS] = 
				   flit_data_output_are_valid[node_num+(NUM_OF_NODES>>1)][ACROSS];

			assign adjacent_node_vc_are_full[node_num][ACROSS*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS] =
				   current_node_vc_are_full[node_num+(NUM_OF_NODES>>1)][ACROSS*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS];

			assign adjacent_nodes_are_ready[node_num][ACROSS*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS] =
				   current_node_is_ready[node_num+(NUM_OF_NODES>>1)][ACROSS*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS];
		end


		spidergon_node
		#( 
			.NUM_OF_NODES(NUM_OF_NODES), 
			.FLIT_DATA_WIDTH(FLIT_DATA_WIDTH),
			.NODE_BUFFER_WIDTH(NODE_BUFFER_WIDTH),
			.NODE_IDENTIFIER(node_num), 
			.NUM_OF_VIRTUAL_CHANNELS(NUM_OF_VIRTUAL_CHANNELS)
		) 
		SPnode
		(
			.clk(clk), .reset(reset), 

			`ifdef FORMAL
			.input_flit_type(input_flit_type[node_num]),
			.out_port_num(out_port_num[node_num]),
			`endif

		 	.flit_data_input_across(flit_data_input[node_num][ACROSS]), 
		 	.flit_data_input_clockwise(flit_data_input[node_num][CLOCKWISE]), 
		 	.flit_data_input_anticlockwise(flit_data_input[node_num][ANTI_CLOCKWISE]), 

			.flit_data_input_are_valid(flit_data_input_are_valid[node_num]),

			.flit_data_output_across(flit_data_output[node_num][ACROSS]),
		 	.flit_data_output_clockwise(flit_data_output[node_num][CLOCKWISE]),
		 	.flit_data_output_anticlockwise(flit_data_output[node_num][ANTI_CLOCKWISE]),

			.node_data_from_cpu(node_data_from_cpu[node_num]),
			.node_data_to_cpu(node_data_to_cpu[node_num]),
			
			.data_input(data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH]),


			// http://www.lisnoc.org/flowcontrol.html ON/OFF flow control
			// sender node asserts 'valid' signal when it has data to send to its neighbouring node
			// receipient node asserts 'ready' signal when it has available buffer space

			// 'ready' output signals
			.current_node_is_ready(current_node_is_ready[node_num]),

			// 'valid' output signals
			.flit_data_output_are_valid(flit_data_output_are_valid[node_num]),

			// 'ready' input signals from next immediate nodes in transit along the transmission path
			.adjacent_nodes_are_ready(adjacent_nodes_are_ready[node_num]),

			// backpressure signals
			.current_node_vc_are_full(current_node_vc_are_full[node_num]),  // output
			.adjacent_node_vc_are_full(adjacent_node_vc_are_full[node_num]) // input
		);


		// What about packet-retransmission due to data CRC integrity error ?
		// will implement this later because the consequences of such a rare failure 
		// are not high enough to justify effort to mitigate it now


		// See the overall spidergon hardware architecture at https://i.imgur.com/6d9E1JT.png
		// for Spidergon NoC functional verification and testing only, 
		// use user-defined module below otherwise

		always @(posedge clk) 
			node_data_from_cpu[node_num] <= node_data_to_cpu[node_num];

		// user-defined module (arithmetic operations) within each Spidergon node
		/*spidergon_node_cpu SP_cpu()*/


		`ifdef FORMAL
		//initial	assume(data_input[((node_num+1)*FLIT_TOTAL_WIDTH-1) -: HEAD_TAIL] == HEADER);

	    always@(posedge clk)
		begin
	        if(first_clock_had_passed && $past(reset)) 
	        	assume(data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH] == 
	                    {HEADER, node_num[DEST_NODE_WIDTH-1:0], 
						{(FLIT_TOTAL_WIDTH-HEAD_TAIL-DEST_NODE_WIDTH-1){1'b0}});	 

			else assume(data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH] == 0);
		end

		// multi-hop verification for deadlock check

		integer dest_ports, source_node_num;

		always @(posedge clk)
		begin
			if(reset) data_packet_contains_header[node_num] <= 0;

			else begin

				for(dest_ports = 0; dest_ports < NUM_OF_PORTS; dest_ports = dest_ports + 1)
				begin
					if((input_flit_type[node_num][dest_ports*HEAD_TAIL +: HEAD_TAIL] == HEAD_FLIT) ||
					   (input_flit_type[node_num][dest_ports*HEAD_TAIL +: HEAD_TAIL] == HEADER))

						data_packet_contains_header[node_num] <= 1;
				end
			end
		end


		always @(posedge clk)
		begin
			if(reset) destination_address_matches[node_num] <= 0;
	
			else if(node_num == 
						data_input[((node_num+1)*FLIT_TOTAL_WIDTH-HEAD_TAIL-$clog2(NUM_OF_VIRTUAL_CHANNELS)-1) -: DEST_NODE_WIDTH])
						
				destination_address_matches[node_num] <= 1;
		end


		assign packet_arrived_at_dest[node_num] = (first_clock_had_passed &&
				(data_packet_contains_header[node_num]) && (destination_address_matches[node_num]));

		integer port_num;

		always @(posedge clk)
		begin
			if(first_clock_had_passed && $past(reset)) 
			begin
				for(port_num=0; port_num<NUM_OF_PORTS; port_num=port_num+1)
				begin
					if((port_num == out_port_num[node_num][port_num*DIRECTION_WIDTH +: DIRECTION_WIDTH])
						&& flit_data_output_are_valid[node_num][port_num])
						assert(flit_data_output[node_num][port_num] == node_data_from_cpu[node_num]);
					
					else assert(flit_data_output[node_num][port_num] == 0);
				end
			end

			else if(packet_arrived_at_dest[node_num]) begin // reaching destination node

				// use 'b1xx since a node can receive packets from 
				// all three incoming ports in the same clock cyle

				case (flit_data_input_are_valid[node_num])

					'bxx1 : assert(flit_data_input[node_num][ACROSS] == 
									data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH]);

					'bx1x : assert(flit_data_input[node_num][CLOCKWISE] == 
									data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH]);

					'b1xx : assert(flit_data_input[node_num][ANTI_CLOCKWISE] == 
									data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH]);

					//default : assert(1);// don't care when it is 'b000 since no data is received yet

				endcase

			end

			// verify the correctness of single-hop routing between two neighbour nodes
			else begin

				//assert();

			end
		end

		// single data packet traversing the NoC and reached its destination successfully
		always @(posedge clk) cover(packet_arrived_at_dest[node_num]);
		always @(posedge clk) cover(data_packet_contains_header[node_num]);
		//always @(posedge clk) cover(destination_address_matches[node_num]);
		`endif

	end

endgenerate


`ifdef FORMAL

// multiple data packets traversing the NoC and reached their destination successfully
always @(posedge clk) cover(&packet_arrived_at_dest);

`endif

endmodule
