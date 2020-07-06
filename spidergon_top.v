// https://www.reddit.com/r/algorithms/comments/au94ak/spidergon_networksonchips/

module spidergon_top 
#(
	`ifdef FORMAL	
		parameter NUM_OF_NODES=8, 
		parameter FLIT_DATA_WIDTH=12,
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
localparam FLIT_TOTAL_WIDTH = HEAD_TAIL+$clog2(NUM_OF_VIRTUAL_CHANNELS)+FLIT_DATA_WIDTH;

localparam DIRECTION_WIDTH = 2; // $clog2(NUM_OF_PORTS)
localparam NUM_OF_PORTS = 3; // clockwise, anti-clockwise, across

localparam STOP = 3;
localparam ACROSS = 2;
localparam CLOCKWISE = 1;
localparam ANTI_CLOCKWISE = 0;

// for user application mapping, this value must be smaller than NUM_OF_NODES
localparam NUM_OF_INPUTS = 16;

localparam CRC_BITWIDTH = 3; // CRC-3 output bitwidth


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

reg [NUM_OF_PORTS-1:0] packet_arrived_at_dest [NUM_OF_NODES-1:0];

reg [NUM_OF_NODES-1:0] data_packet_contains_header;
reg [NUM_OF_PORTS-1:0] destination_address_matches [NUM_OF_NODES-1:0];

initial data_packet_contains_header = 0;
//initial destination_address_matches = 0;


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

		`ifdef FORMAL
		
		// CRC-3 computation check occurs whenever a data packet goes from one node to the next node
		
		localparam CRC_INPUT_BITWIDTH = FLIT_TOTAL_WIDTH-HEAD_TAIL-$clog2(NUM_OF_VIRTUAL_CHANNELS);
		
		integer crc_array_bit_location;
		
		generate
			genvar port_num;

			for(port_num = 0; port_num < NUM_OF_PORTS; port_num = port_num + 1)
			begin : CRC
			
				wire [CRC_BITWIDTH:0] crc_3_divisor = 'b1011;
			
				wire [CRC_INPUT_BITWIDTH-1:0] crc_calculation_input
					= flit_data_input[node_num][port_num][0 +: CRC_INPUT_BITWIDTH];
			
				reg [CRC_INPUT_BITWIDTH-1:0] crc_intermediate_result;
				wire [CRC_BITWIDTH-1:0] crc_final_result = crc_intermediate_result[0 +: CRC_BITWIDTH];
			
				always @(posedge clk) 
					if(first_clock_had_passed && flit_data_input_are_valid[node_num][port_num])
						assert(crc_final_result == 0); // no CRC data integrity error
				
			
				// CRC-3 https://en.wikipedia.org/wiki/Cyclic_redundancy_check#Computation
				always @(*)
				begin
					if(flit_data_input_are_valid[node_num][port_num])
					begin
						// this is only for formal verification of the NoC, 
						// so it does not matter if the CRC-3 code is not hardware-friendly
						// and CRC-3 will not be computed during actual hardware running
						// at least in current hardware design
						
						crc_intermediate_result = crc_calculation_input;
						
						for(crc_array_bit_location = (CRC_INPUT_BITWIDTH-1); 
						    crc_array_bit_location >= CRC_BITWIDTH;
							crc_array_bit_location = crc_array_bit_location - 1)
						begin
							if(crc_intermediate_result[crc_array_bit_location])
							begin
								crc_intermediate_result = 
								crc_intermediate_result ^ 
								{{(CRC_INPUT_BITWIDTH-crc_array_bit_location-1){1'b0}}, crc_3_divisor, 
         					 	 {(crc_array_bit_location-CRC_BITWIDTH){1'b0}}};
							end
						end
					end
				end
			end
			
		endgenerate
		
		`endif


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
			               {
								HEADER, 
								{$clog2(NUM_OF_VIRTUAL_CHANNELS){1'b0}}, // assume the first VC
		 				 		node_num[DEST_NODE_WIDTH-1:0], 
					 			{(FLIT_TOTAL_WIDTH-HEAD_TAIL-$clog2(NUM_OF_VIRTUAL_CHANNELS)-
								 DEST_NODE_WIDTH-1){1'b0}}
							});	 

			else assume(data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH] == 0);
		end

		// multi-hop verification for deadlock check

		integer dest_ports;

		always @(*)
		begin
			if(reset) data_packet_contains_header[node_num] = 0;

			else begin

				for(dest_ports = 0; dest_ports < NUM_OF_PORTS; dest_ports = dest_ports + 1)
				begin
					if((input_flit_type[node_num][dest_ports*HEAD_TAIL +: HEAD_TAIL] == HEAD_FLIT) ||
					   (input_flit_type[node_num][dest_ports*HEAD_TAIL +: HEAD_TAIL] == HEADER))

						data_packet_contains_header[node_num] = 1;
				end
			end
		end


		always @(*)
		begin							
			for(dest_ports = 0; dest_ports < NUM_OF_PORTS; dest_ports = dest_ports + 1)
			begin
				destination_address_matches[node_num][dest_ports] = 0; // try to reset before checking
			
				if((node_num == flit_data_input[node_num][dest_ports][(FLIT_DATA_WIDTH-1) -: DEST_NODE_WIDTH])
					&& flit_data_input_are_valid[node_num][dest_ports])

					destination_address_matches[node_num][dest_ports] = 1;
			end
		end

		always @(*) 
		begin
			for(dest_ports = 0; dest_ports < NUM_OF_PORTS; dest_ports = dest_ports + 1)
			begin
				packet_arrived_at_dest[node_num][dest_ports] = (first_clock_had_passed &&
								(data_packet_contains_header[node_num]) && 
								(destination_address_matches[node_num][dest_ports]));
			end
		end

		integer port_nums;

		always @(posedge clk)
		begin
			if(first_clock_had_passed && $past(reset)) 
			begin
				for(port_nums=0; port_nums<NUM_OF_PORTS; port_nums=port_nums+1)
				begin
					if((port_nums == 
					   $past(out_port_num[node_num][port_nums*DIRECTION_WIDTH +: DIRECTION_WIDTH]))
						&& flit_data_output_are_valid[node_num][port_nums])

							assert(flit_data_output[node_num][port_nums] ==
		 							node_data_from_cpu[node_num]);
					
					else assert(flit_data_output[node_num][port_nums] == 0);
				end
			end

			else if(|packet_arrived_at_dest[node_num]) begin // reaching destination node
				// 'case()' is not used here because multiple data packets could arrive in the same clock cycle

				if(packet_arrived_at_dest[node_num][ACROSS])
					assert(flit_data_input[node_num][ACROSS][(FLIT_DATA_WIDTH-1) -:
					 		DEST_NODE_WIDTH] == node_num[DEST_NODE_WIDTH-1:0]);

				if(packet_arrived_at_dest[node_num][CLOCKWISE])
					assert(flit_data_input[node_num][CLOCKWISE][(FLIT_DATA_WIDTH-1) -:
					 		DEST_NODE_WIDTH] == node_num[DEST_NODE_WIDTH-1:0]);

				if(packet_arrived_at_dest[node_num][ANTI_CLOCKWISE])
					assert(flit_data_input[node_num][ANTI_CLOCKWISE][(FLIT_DATA_WIDTH-1) -:
					 		DEST_NODE_WIDTH] == node_num[DEST_NODE_WIDTH-1:0]);
			end

			// verify the correctness of single-hop routing between two neighbour nodes
			else begin

				//assert();

			end
		end

		// single data packet traversing the NoC and reached its destination successfully
		always @(posedge clk) cover(|packet_arrived_at_dest[node_num]);			
		always @(posedge clk) cover(|destination_address_matches[node_num]);
		always @(posedge clk) cover(data_packet_contains_header[node_num]);
		
		// multiple data packets traversing the NoC and reached their destination successfully
		always @(posedge clk) cover(&packet_arrived_at_dest[node_num]);
		
		`endif
	end

endgenerate


`ifdef FORMAL

/* deadlock check */
localparam MAX_NUM_OF_ALLOWABLE_IN_PROGRESS_DATA_PACKETS = 32;
reg [$clog2(MAX_NUM_OF_ALLOWABLE_IN_PROGRESS_DATA_PACKETS):0] 
			 num_of_in_progress_data_packets [NUM_OF_NODES-1:0];

reg [$clog2(MAX_NUM_OF_ALLOWABLE_IN_PROGRESS_DATA_PACKETS):0] 
			 current_num_of_in_progress_data_packets [NUM_OF_NODES-1:0];

reg possible_deadlock_scenario [NUM_OF_NODES-1:0];

generate
	genvar node_num;

	for(node_num = 0; node_num < NUM_OF_NODES; node_num = node_num + 1) 
	begin : DEADLOCK

		initial possible_deadlock_scenario[node_num] = 0;
		initial num_of_in_progress_data_packets[node_num] = 0;

		always @(posedge clk)
		begin
			if(reset) current_num_of_in_progress_data_packets[node_num] <= 0;
		
			else current_num_of_in_progress_data_packets[node_num] <= num_of_in_progress_data_packets[node_num];
		end

		always @(posedge clk)
		begin
			if(first_clock_had_passed)
			begin
				if($past(reset)) assert(current_num_of_in_progress_data_packets[node_num] == 0);
			
				else assert(current_num_of_in_progress_data_packets[node_num] ==
				 			$past(num_of_in_progress_data_packets[node_num]));
			end
		end

		always @(posedge clk)
		begin
			if(reset) possible_deadlock_scenario[node_num] <= 0;
			
			else if(num_of_in_progress_data_packets[node_num] >= MAX_NUM_OF_ALLOWABLE_IN_PROGRESS_DATA_PACKETS)
				possible_deadlock_scenario[node_num] <= 1;
		end

		always @(posedge clk) 
		begin
			assert(possible_deadlock_scenario[node_num] == 0);
			cover(possible_deadlock_scenario[node_num]); // trying to get waveform in case of deadlock
		end
	end
endgenerate


wire [DEST_NODE_WIDTH-1:0] source_address_in_input_flit [NUM_OF_NODES-1:0][NUM_OF_PORTS-1:0]; // source node
wire [DEST_NODE_WIDTH-1:0] destination_address_in_output_flit [NUM_OF_NODES-1:0][NUM_OF_PORTS-1:0]; // dest node
wire [DEST_NODE_WIDTH-1:0] source_address_in_output_flit [NUM_OF_NODES-1:0][NUM_OF_PORTS-1:0]; // source node

(* keep *) wire [NUM_OF_NODES*NUM_OF_PORTS-1:0] flit_data_output_contains_header;
wire [NUM_OF_NODES*NUM_OF_PORTS-1:0] flit_data_input_contains_header;
wire [NUM_OF_NODES*NUM_OF_PORTS-1:0] flit_data_input_contains_tail;

wire [NUM_OF_PORTS-1:0] node_sending_data_to_other_nodes [NUM_OF_NODES-1:0];

generate

	genvar node_num, port_num;

	for(node_num = 0; node_num < NUM_OF_NODES; node_num = node_num + 1) 
	begin : NODES
	
		initial node_data_from_cpu[node_num] = 0;
	
		for(port_num = 0; port_num < NUM_OF_PORTS; port_num = port_num + 1)
		begin : PORTS
		
			assign flit_data_output_contains_header[node_num*NUM_OF_PORTS + port_num] =
						((flit_data_output[node_num][port_num][(FLIT_TOTAL_WIDTH-1) -: HEAD_TAIL] == HEADER) || 
						(flit_data_output[node_num][port_num][(FLIT_TOTAL_WIDTH-1) -: HEAD_TAIL] == HEAD_FLIT));
				
			assign flit_data_input_contains_header[node_num*NUM_OF_PORTS + port_num] =
						((flit_data_input[node_num][port_num][(FLIT_TOTAL_WIDTH-1) -: HEAD_TAIL] == HEADER) || 
						(flit_data_input[node_num][port_num][(FLIT_TOTAL_WIDTH-1) -: HEAD_TAIL] == HEAD_FLIT));
				
			assign flit_data_input_contains_tail[node_num*NUM_OF_PORTS + port_num] =
						(flit_data_input[node_num][port_num][(FLIT_TOTAL_WIDTH-1) -: HEAD_TAIL] == TAIL_FLIT);
		
			// head flit format as follows: {01, prev_vc, destination_node, source_node, 9 bits of data_payload}

			assign destination_address_in_output_flit[node_num][port_num] = 
						flit_data_output[node_num][port_num][(FLIT_DATA_WIDTH-1) -: $clog2(NUM_OF_NODES)];

			assign source_address_in_output_flit[node_num][port_num] = 
						flit_data_output[node_num][port_num][(FLIT_DATA_WIDTH-1-$clog2(NUM_OF_NODES)) -:
				 											$clog2(NUM_OF_NODES)];

			assign source_address_in_input_flit[node_num][port_num] = 
						flit_data_input[node_num][port_num][(FLIT_DATA_WIDTH-1-$clog2(NUM_OF_NODES)) -: 
															$clog2(NUM_OF_NODES)];
															
			assign node_sending_data_to_other_nodes[node_num][port_num] =
						source_address_in_output_flit[source_node_num][port_num] !=
						destination_address_in_output_flit[source_node_num][port_num];
		end
	end
	
endgenerate


integer source_node_num, other_nodes_num, port_nums;

always @(*)
begin
	// sum up the number of data packet that originate from source node, and ends in destination node
	// this is to track any in-progress data packets that had been sent out by a particular source node
	// but not received yet by some other nodes other than the source node

	for (source_node_num = 0; source_node_num < NUM_OF_NODES; source_node_num = source_node_num + 1) 
	begin

		for(port_nums = 0; port_nums < NUM_OF_PORTS; port_nums = port_nums + 1)
		begin
			// to avoid logic loop error during synthesis
			num_of_in_progress_data_packets[source_node_num] = 
			current_num_of_in_progress_data_packets[source_node_num];
		
			//if(reset) num_of_in_progress_data_packets[source_node_num] = 0;
			
				/* source node had just sent a data packet header */

				if(flit_data_output_contains_header[source_node_num*NUM_OF_PORTS + port_nums] && 
				   (source_address_in_output_flit[source_node_num][port_nums] == source_node_num) &&
				    flit_data_output_are_valid[source_node_num][port_nums])
				  
			  			num_of_in_progress_data_packets[source_node_num] =
			  			num_of_in_progress_data_packets[source_node_num] + 1;
		end
	end
	
	for (other_nodes_num = 0; other_nodes_num < NUM_OF_NODES; other_nodes_num = other_nodes_num + 1) 
	begin
	
		for(port_nums = 0; port_nums < NUM_OF_PORTS; port_nums = port_nums + 1)
		begin
			//if(node_sending_data_to_other_nodes[source_node_num][port_nums]) begin

				/* destination node had just received the entire data packet */
				
				if(flit_data_input_contains_tail[other_nodes_num*NUM_OF_PORTS + port_nums] &&
				   (source_address_in_input_flit[other_nodes_num][port_nums] == source_node_num) && 
				   flit_data_input_are_valid[other_nodes_num][port_nums] &&
				   (packet_arrived_at_dest[source_node_num]))

			  			num_of_in_progress_data_packets[source_node_num] =
			  			num_of_in_progress_data_packets[source_node_num] - 1;
			//end
	  	end
	end
end

`endif

endmodule
