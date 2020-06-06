// a single node within the Spidergon

module spidergon_node
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

	parameter NODE_IDENTIFIER=0,  
	parameter NUM_OF_VIRTUAL_CHANNELS=2 // 2 vc for each input ports of each node
) 
(
	clk, reset, 
	`ifdef FORMAL
	input_flit_type,
	out_port_num,
	`endif
 	flit_data_input_across, flit_data_input_clockwise, flit_data_input_anticlockwise,
 	flit_data_output_across, flit_data_output_clockwise, flit_data_output_anticlockwise, 
	node_data_from_cpu, node_data_to_cpu, data_input,
	flit_data_input_are_valid, flit_data_output_are_valid,
	current_node_is_ready, adjacent_nodes_are_ready,
	current_node_vc_are_full, adjacent_node_vc_are_full
);


parameter DEST_NODE_WIDTH = $clog2(NUM_OF_NODES);
parameter VIRTUAL_CHANNELS_BITWIDTH = $clog2(NUM_OF_VIRTUAL_CHANNELS);


localparam STOP = 3;
localparam ACROSS = 2;
localparam CLOCKWISE = 1;
localparam ANTI_CLOCKWISE = 0;


// the most significant two bits are to indicate head and/or tail flits,
// followed by dest_node and flit_data_payload
// See http://www.lisnoc.org/packets.html

// 01 = head_flit , 10 = data_flit (body_flit), 00 = tail_flit, 11 = flit_without_data_payload
localparam HEAD_FLIT = 2'b01;
localparam HEADER = 2'b11; // flit_without_data_payload
localparam BODY_FLIT = 2'b10;
localparam TAIL_FLIT = 2'b00;

localparam HEAD_TAIL = 2;
localparam FLIT_TOTAL_WIDTH = HEAD_TAIL+$clog2(NUM_OF_VIRTUAL_CHANNELS)+FLIT_DATA_WIDTH;


localparam NUM_OF_PORTS = 3; // clockwise, anti-clockwise, across
localparam BIDIRECTIONAL_PER_PORT = 2; // two-way data traffic


input clk, reset;

input [FLIT_TOTAL_WIDTH-1:0] data_input;

input [FLIT_TOTAL_WIDTH-1:0] flit_data_input_across;
input [FLIT_TOTAL_WIDTH-1:0] flit_data_input_clockwise;
input [FLIT_TOTAL_WIDTH-1:0] flit_data_input_anticlockwise;

input [FLIT_TOTAL_WIDTH-1:0] node_data_from_cpu;
output reg [FLIT_TOTAL_WIDTH-1:0] node_data_to_cpu;

output [FLIT_TOTAL_WIDTH-1:0] flit_data_output_across;
output [FLIT_TOTAL_WIDTH-1:0] flit_data_output_clockwise;
output [FLIT_TOTAL_WIDTH-1:0] flit_data_output_anticlockwise;

input [NUM_OF_PORTS-1:0] flit_data_input_are_valid;
output [NUM_OF_PORTS-1:0] flit_data_output_are_valid;

// adjacent nodes can accept new head flit to reserve one virtual channel
input [NUM_OF_PORTS*NUM_OF_VIRTUAL_CHANNELS-1:0] adjacent_nodes_are_ready;

// current node can accept new head flit to reserve one virtual channel
output [NUM_OF_PORTS*NUM_OF_VIRTUAL_CHANNELS-1:0] current_node_is_ready;

// to indicate to the node about the virtual channel buffers fill status
input [NUM_OF_PORTS*NUM_OF_VIRTUAL_CHANNELS-1:0] adjacent_node_vc_are_full;
output [NUM_OF_PORTS*NUM_OF_VIRTUAL_CHANNELS-1:0] current_node_vc_are_full;


`ifdef FORMAL
	output [NUM_OF_PORTS*HEAD_TAIL-1:0] input_flit_type;
	output [NUM_OF_PORTS*DIRECTION_WIDTH-1:0] out_port_num;
`else
	wire [NUM_OF_PORTS*HEAD_TAIL-1:0] input_flit_type;
	//wire [NUM_OF_PORTS*DIRECTION_WIDTH-1:0] out_port_num;
`endif


wire [NUM_OF_PORTS-1:0] valid_output;
reg [NUM_OF_PORTS-1:0] valid_output_previously;

wire [FLIT_TOTAL_WIDTH-1:0] flit_data_input [NUM_OF_PORTS-1:0];
reg [FLIT_TOTAL_WIDTH-1:0] flit_data_output [NUM_OF_PORTS-1:0];


assign flit_data_input[ACROSS] = flit_data_input_across;
assign flit_data_input[CLOCKWISE] = flit_data_input_clockwise;
assign flit_data_input[ANTI_CLOCKWISE] = flit_data_input_anticlockwise;

assign flit_data_output_across = flit_data_output[ACROSS];
assign flit_data_output_clockwise = flit_data_output[CLOCKWISE];
assign flit_data_output_anticlockwise = flit_data_output[ANTI_CLOCKWISE];


// these virtual channel buffers are at input port side
wire [FLIT_TOTAL_WIDTH-1:0] data_output_from_vc [NUM_OF_PORTS-1:0][NUM_OF_VIRTUAL_CHANNELS-1:0];
wire [FLIT_TOTAL_WIDTH-1:0] data_input_to_vc [NUM_OF_PORTS-1:0][NUM_OF_VIRTUAL_CHANNELS-1:0];

wire [NUM_OF_VIRTUAL_CHANNELS-1:0] vc_is_available [NUM_OF_PORTS-1:0]; // vc is not BUSY
wire [NUM_OF_VIRTUAL_CHANNELS-1:0] vc_buffer_is_empty [NUM_OF_PORTS-1:0]; // no flits inside vc

// requests for the input data (from one of the 3 input ports) 
// to be routed to  destination node (via one of the 3 output ports)
// this 'req' is not a one-hot vector: reg [vc_num] req [out_port];
// multiple input data streams from different virtual channels could compete for the same output port
reg [NUM_OF_VIRTUAL_CHANNELS-1:0] req [NUM_OF_PORTS-1:0];

reg [NUM_OF_VIRTUAL_CHANNELS-1:0] req_previous [NUM_OF_PORTS-1:0];


wire [NUM_OF_VIRTUAL_CHANNELS-1:0] vc_is_to_be_allocated [NUM_OF_PORTS-1:0];
wire [NUM_OF_VIRTUAL_CHANNELS-1:0] vc_is_to_be_deallocated [NUM_OF_PORTS-1:0];


localparam DIRECTION_WIDTH = 2;
wire [DIRECTION_WIDTH-1:0] direction [NUM_OF_PORTS-1:0]; // stop, clockwise, anti-clockwise, across

wire [DEST_NODE_WIDTH-1:0] dest_node [NUM_OF_PORTS-1:0];


localparam NON_EXISTENCE_VC_NUM = {(NUM_OF_VIRTUAL_CHANNELS+1){1'b1}};


wire [NUM_OF_PORTS-1:0] req_port;

// note that 'grant' is one-hot vector, 
// when asserted, it means the corresponding 'req' is approved/granted
// and only a single priority line is serviced (granted) at any given clock cycle
wire [NUM_OF_VIRTUAL_CHANNELS-1:0] granted_vc [NUM_OF_PORTS-1:0];
wire [NUM_OF_PORTS-1:0] granted_port;

// binary encoding of 'granted_vc' and 'granted_port'. Refer to module 'oh_to_idx'
wire [$clog2(NUM_OF_VIRTUAL_CHANNELS)-1:0] granted_vc_index [NUM_OF_PORTS-1:0];
wire [$clog2(NUM_OF_PORTS)-1:0] granted_port_index;


// for detecting if all outstanding requests are already served
wire [NUM_OF_PORTS-1:0] requests_in_ports_have_been_served = req_port & granted_port;
wire [NUM_OF_PORTS-1:0] outstanding_requests_in_multiple_ports = req_port - granted_port;
//wire [NUM_OF_VIRTUAL_CHANNELS-1:0] outstanding_requests_in_multiple_vcs =
//							 		req[granted_port_index] - granted_vc[granted_port_index];

// https://graphics.stanford.edu/~seander/bithacks.html#DetermineIfPowerOf2
wire requests_from_multiple_ports = !((req_port != 0) && ((req_port & (req_port - 1)) == 0));


// Ports round-robin arbitration (maps port to cpu)
arbiter #(NUM_OF_PORTS) rr_arb_port_to_cpu
(.clk(clk), .reset(reset), .req(outstanding_requests_in_multiple_ports), .grant(granted_port));


// for one-hot encoding to binary encoding conversion
oh_to_idx #(NUM_OF_PORTS) port_index (.one_hot(granted_port), .index(granted_port_index));



reg [NUM_OF_PORTS-1:0] past_req_port;
always @(posedge clk) past_req_port <= req_port;

always @(*)
begin
	if(reset & reset_previously)
		node_data_to_cpu = data_input;

	else if(reset || (past_req_port == 0)) node_data_to_cpu = 0;

	else node_data_to_cpu = data_output_from_vc[granted_port_index][granted_vc_index[granted_port_index]];
end


wire [$clog2(NUM_OF_NODES)-1:0] current_node = NODE_IDENTIFIER;

// 'reset' signal spans across 2 clock cycles for correct fifo reset operation before inserting item into fifo
// 'reset_previously' is used together with 'reset' to identify falling edge of 'reset'
reg reset_previously;
always @(posedge clk) reset_previously <= reset;


wire [NUM_OF_PORTS-1:0] node_needs_to_send_its_own_data; // there are 'NUM_OF_PORTS' ports to send data to
reg [NUM_OF_PORTS-1:0] node_needs_to_send_its_own_data_previously;
wire [FLIT_TOTAL_WIDTH-1:0] node_own_data [NUM_OF_PORTS-1:0];


// note that flits from the same data packet cannot be interleaved 
// among different virtual channels
// Why ? Because of head flit and tail flit indication

// let FLIT_DATA_WIDTH = 16 in the discussion below:
// let HEAD_TAIL = 2  to indicate flit type
// let FLIT_TOTAL_WIDTH = HEAD_TAIL + FLIT_DATA_WIDTH

// 18-bit head flit format as follows: {01, prev_vc, destination_node, source_node, 9 bits of data_payload}
// prev_vc consumes 1 bit, destination_node or source node consume 3 bits (8 nodes in total), 
// so we are left with 9 bits in the head flit
// these 9 bits could be data payload as well

// 18-bit body flit format as follows: {10, prev_vc, 15 bits of data_payload}
// 18-bit tail flit format as follows: {00, prev_vc, 15 bits of data_payload}
// So, a single body_flit or tail_flit could carry 15 bits of data payload
// tail flit will deallocate all the virtual channels along the path to the destination nodes

// for wormhole switching flow control purpose 
// basically each node itself need to remember(store) exactly which header 
// allocates which virtual channel, and this storing has to be coherent for 
// previous and current nodes due to wormhole switching requirement

/* 
	A vc allocation table for current node (imagine the use of linked-list data structure)

	Current_Port    Current_VC		Prev_VC		BUSY 	FULL

	ACROSS				0			X			X		X
	ACROSS				1			X			X		X

	CLOCKWISE			0			X			X		X
	CLOCKWISE			1			X			X		X

	ANTI_CLOCKWISE		0			X			X		X
	ANTI_CLOCKWISE		1			X			X		X


	Note: 
	1. The head flit contains Prev_VC (no need for Prev_Port since we can deduce from Current_Port)
	2. Once a Current_VC is reserved by head flit, the corresponding table entry is filled
	3. Once a Current_VC is de-reserved by tail flit, the corresponding table entry is updated
	4. BUSY and FULL signals are for Current_VC, not for Prev_VC
	5. A table costs 36 bits (NUM_OF_ROWS*(2+1+1+1+1))
*/


genvar port_num;
genvar vc_num;

generate

	for(port_num=0; port_num<NUM_OF_PORTS; port_num=port_num+1)
	begin : PORTS	


		// remember that each ports have multiple vc
		// virtual channel (VC) outgoing buffers round-robin arbitration (maps vc in port to cpu)
		arbiter #(NUM_OF_VIRTUAL_CHANNELS) rr_arb_vc_to_cpu
		(.clk(clk), .reset(reset), 
		 .req(req[port_num]), 
		 .grant(granted_vc[port_num]));


		// for one-hot encoding to binary encoding conversion

		oh_to_idx #(NUM_OF_VIRTUAL_CHANNELS) vc_index 
		(
			.one_hot(granted_vc[port_num]), 
			.index(granted_vc_index[port_num])
		);


		`ifdef FORMAL
			assign out_port_num[port_num*DIRECTION_WIDTH +: DIRECTION_WIDTH] = direction[port_num];
		`endif

		// asserted whenever one of the virtual channels in each port is reserved
		assign req_port[port_num] = |req[port_num]; 


		assign input_flit_type[port_num*HEAD_TAIL +: HEAD_TAIL] = 
						flit_data_input[port_num][(FLIT_TOTAL_WIDTH-1) -: HEAD_TAIL] ;

		// virtual channel index at previous node
		wire prev_vc = 
				flit_data_input[port_num][(FLIT_DATA_WIDTH-1) -: VIRTUAL_CHANNELS_BITWIDTH] ;


		wire [NUM_OF_VIRTUAL_CHANNELS-1:0] adjacent_nodes_vc_are_reserved_and_not_full;

		wire [NUM_OF_VIRTUAL_CHANNELS-1:0] granted_vc_enqueue; // to indicate which vc to reserve

		// remember that each ports have multiple vc
		// virtual channel (VC) incoming buffers round-robin arbitration (maps incoming data to vc)
		arbiter #(NUM_OF_VIRTUAL_CHANNELS) rr_arb_data_to_vc
		(
			.clk(clk), 
			.reset(reset), 
		 	.req(current_node_is_ready[port_num*NUM_OF_VIRTUAL_CHANNELS +: NUM_OF_VIRTUAL_CHANNELS]), 
		 	.grant(granted_vc_enqueue)
		);


		wire [NUM_OF_VIRTUAL_CHANNELS-1:0] previous_vc;

		for(vc_num=0; vc_num<NUM_OF_VIRTUAL_CHANNELS; vc_num=vc_num+1)
		begin : VIRTUAL_CHANNELS

			// ON/OFF flow control
			// to indicate whether flit data could come into the node

			// (vc buffer is not reserved)
			assign current_node_is_ready[port_num*NUM_OF_VIRTUAL_CHANNELS + vc_num] =
					vc_is_available[port_num][vc_num];


			// (the next node has at least one available, non-reserved vc) OR 
			// (any of the reserved vc (at next node) has sufficient buffer space)	
			// AND (to prevent competition of virtual channels for CPU)
			wire dequeue_en = (direction[port_num] == STOP) ? 1'b0 :
				  (((|adjacent_nodes_are_ready[direction[port_num]*NUM_OF_VIRTUAL_CHANNELS +:
					NUM_OF_VIRTUAL_CHANNELS]) || (|adjacent_nodes_vc_are_reserved_and_not_full))
					&& (!requests_from_multiple_ports ||
						requests_from_multiple_ports &&
					 	requests_in_ports_have_been_served[port_num]));


			assign adjacent_nodes_vc_are_reserved_and_not_full[vc_num] = 
				(direction[port_num] == STOP) ? 1'b0 :					

			  ((!adjacent_nodes_are_ready[direction[port_num]*NUM_OF_VIRTUAL_CHANNELS + vc_num]) 
			  & (!adjacent_node_vc_are_full[direction[port_num]*NUM_OF_VIRTUAL_CHANNELS + vc_num]));


			assign previous_vc[vc_num] = (reset || vc_is_available[port_num][vc_num]) ? 
											1'b0 : prev_vc;


			// enqueues when 'data is valid' && ((available vc is granted permission) || 
			// ('vc is reserved' by the same 'head flit')) && '!current vc is full'

			wire enqueue_en = (!reset & reset_previously) ? 
						flit_data_input_are_valid[port_num] && (vc_num == 0) :

						flit_data_input_are_valid[port_num] &&
						((vc_is_available[port_num][vc_num] && granted_vc_enqueue[vc_num]) ||
						(!vc_is_available[port_num][vc_num] && (prev_vc == previous_vc[vc_num]))) &&

						(!current_node_vc_are_full[port_num*NUM_OF_VIRTUAL_CHANNELS + vc_num]);


			// virtual channel buffer in the form of strict FIFO ordering
			sync_fifo 
			#(
				.WIDTH(FLIT_TOTAL_WIDTH),
				.SIZE(NODE_BUFFER_WIDTH/FLIT_DATA_WIDTH)
			)
			fifo
			(
				.clk(clk), .reset(reset),
				.full(current_node_vc_are_full[port_num*NUM_OF_VIRTUAL_CHANNELS + vc_num]), 
				.enqueue_en(enqueue_en), 
				.enqueue_value(data_input_to_vc[port_num][vc_num]),

				// buffer could be empty even it is reserved, due to flits not arriving yet
				.empty(vc_buffer_is_empty[port_num][vc_num]),
			 	.dequeue_en(dequeue_en), // enabled when the buffers at next node can take in flits
				.dequeue_value(data_output_from_vc[port_num][vc_num])
			);
	
			assign data_input_to_vc[port_num][vc_num] = flit_data_input[port_num];			

			assign vc_is_available[port_num][vc_num] = !req[port_num][vc_num];


			always @(posedge clk) 
			begin
				if(reset) req_previous[port_num][vc_num] <= 0;

				else req_previous[port_num][vc_num] <= req[port_num][vc_num];
			end


			// NOT reserved yet for usage by other flit
			// remember that each header or head flit could only reserve ONE vc in each port
			assign vc_is_to_be_allocated[port_num][vc_num] = (!reset & reset_previously) ? 
					((flit_data_input_are_valid[port_num]) && (vc_num == 0)) :

					(granted_vc_enqueue[vc_num] && (vc_is_available[port_num][vc_num]) && 
					((input_flit_type[port_num*HEAD_TAIL +: HEAD_TAIL] == HEADER) ||
					 (input_flit_type[port_num*HEAD_TAIL +: HEAD_TAIL] == HEAD_FLIT)));


			// vc is already reserved, waiting to be released by tail_flit
			assign vc_is_to_be_deallocated[port_num][vc_num] = 
					(req_previous[port_num][vc_num] && 
					(input_flit_type[port_num*HEAD_TAIL +: HEAD_TAIL] == TAIL_FLIT) &&
					(prev_vc == vc_num)) && (requests_in_ports_have_been_served[port_num]);


			// virtual channel reservation logic block
			always @(posedge clk) 
			begin
				if(reset & reset_previously) req[port_num][vc_num] <= vc_is_to_be_allocated[port_num][vc_num];

				else if ((vc_is_to_be_allocated[port_num][vc_num] && !vc_is_to_be_deallocated[port_num][vc_num]) 
					 || (!vc_is_to_be_allocated[port_num][vc_num] && vc_is_to_be_deallocated[port_num][vc_num]))
				begin

					// HEAD_FLIT or HEADER will reserve the virtual channel
					// BODY_FLIT will not affect the channel reservation status
					// TAIL_FLIT will de-reserve the virtual channel reserved by HEAD_FLIT
					// HEADER will only reserves its virtual channel for single clock cycle

					// check the flit header to determine the flit nature
					case(input_flit_type[port_num*HEAD_TAIL +: HEAD_TAIL]) 
					
						// body_flit
						// to keep 'req' asserted before the arrival of tail_flit
						BODY_FLIT : req[port_num][vc_num] <= 1;

						// tail_flit
						TAIL_FLIT : req[port_num][vc_num] <= 0;

						// head_flit
						HEAD_FLIT : req[port_num][vc_num] <= 1;

						// header flit_without_data_payload
						HEADER : req[port_num][vc_num] <= 1;

						default : req[port_num][vc_num] <= 0;

					endcase
				end

				//else req[port_num][vc_num] <= 0;
			end

			`ifdef FORMAL

			//always @(posedge clk)  cover((vc_num == vc_new) || (vc_num == vc_old));

			`endif

		end


		wire [(HEAD_TAIL-1) : 0] output_flit_type = 
					node_data_from_cpu[(FLIT_TOTAL_WIDTH-1) -: HEAD_TAIL];


		// for the purpose of stopping transaction flow when tail_flit is received
		wire stop_flow = (reset) ?  
						(data_input[FLIT_DATA_WIDTH +: HEAD_TAIL] == TAIL_FLIT) : 
						(output_flit_type == TAIL_FLIT);


		assign dest_node[port_num] = (reset) ? 
				data_input[(FLIT_DATA_WIDTH-1) -: DEST_NODE_WIDTH] :
				flit_data_input[port_num][(FLIT_DATA_WIDTH-1) -: DEST_NODE_WIDTH];

		// path routing computation block for each input ports
		router #(NUM_OF_NODES) rt 
		(
			//.clk(clk),

			// see the math logic in router.v on why we set it to 'current_node' for tail_flit
			.dest_node((stop_flow) ? current_node : dest_node[port_num]), 
			.current_node(current_node), 
			.direction(direction[port_num])
		);


		always @(posedge clk) valid_output_previously[port_num] <= valid_output[port_num];

		// for aligning correctly with 'flit_data_output' in the same clock cycle
		assign flit_data_output_are_valid[port_num] = valid_output_previously[port_num];	

		localparam NUM_OF_CLOCK_CYCLES_BEFORE_SENDING_NODE_OWN_DATA = 8;
		reg [$clog2(NUM_OF_CLOCK_CYCLES_BEFORE_SENDING_NODE_OWN_DATA)-1:0] start_sending_node_own_data;
		
		always @(posedge clk) 
		begin
			if(reset) start_sending_node_own_data <= 0;
			
			else if(~&start_sending_node_own_data)
				start_sending_node_own_data <= start_sending_node_own_data + 1;
		end

		reg [FLIT_TOTAL_WIDTH-HEAD_TAIL-$clog2(NUM_OF_VIRTUAL_CHANNELS)-DEST_NODE_WIDTH-DEST_NODE_WIDTH-1:0]
 				random_generated_data;

		wire [DEST_NODE_WIDTH-1:0] dest_node_for_sending_node_own_data;
		
		`ifdef FORMAL
			always @(posedge clk)
			begin
				if(reset) random_generated_data <= 0;
				 
				else random_generated_data <= $anyconst;
			end
			
			assign dest_node_for_sending_node_own_data = $anyseq; // always less than NUM_OF_NODES
			assign node_needs_to_send_its_own_data[port_num] = $anyseq;	
			assign node_own_data[port_num] = 
					{
						HEADER, {$clog2(NUM_OF_VIRTUAL_CHANNELS){1'b0}}, 
					 	dest_node_for_sending_node_own_data, // destination node
						current_node, // source node

						random_generated_data
					};		
		`else
			always @(posedge clk)
			begin
				if(reset) random_generated_data <= 0;
				 
				else random_generated_data <= random_generated_data + 1; // just for randomness
			end
				
			assign dest_node_for_sending_node_own_data = 0; // keeps sending to node #0
			assign node_needs_to_send_its_own_data[port_num] = (&start_sending_node_own_data); // keeps sending out own data
			assign node_own_data[port_num] = 
					{
						HEADER, {$clog2(NUM_OF_VIRTUAL_CHANNELS){1'b0}}, 
					 	dest_node_for_sending_node_own_data, // destination node
						current_node, // source node
						
						random_generated_data+
						{{(FLIT_TOTAL_WIDTH-HEAD_TAIL-$clog2(NUM_OF_VIRTUAL_CHANNELS)-
 						DEST_NODE_WIDTH-DEST_NODE_WIDTH-NUM_OF_PORTS){1'b0}},
			 	  		port_num[NUM_OF_PORTS-1:0]} // adding port_num is for data randomness
					}; 	
		`endif		

		always @(posedge clk) 
			node_needs_to_send_its_own_data_previously[port_num] <= node_needs_to_send_its_own_data[port_num];

		// needs some backpressure logic here
		assign valid_output[port_num] = (reset) ? 

					(direction[port_num] == port_num) && 
					((output_flit_type == HEAD_FLIT) || (output_flit_type == HEADER)) :

					((direction[port_num] == port_num) && 
					(((output_flit_type == HEAD_FLIT) || (output_flit_type == HEADER)) ||
					(valid_output_previously[port_num] && 
					 (output_flit_type == BODY_FLIT)))) ||
					 node_needs_to_send_its_own_data_previously[port_num];


		always @(posedge clk)
		begin
			//flit_data_output[port_num] <= 0; // clears data in all channels first

			if(reset) 
			begin
				if(valid_output[port_num])
					flit_data_output[port_num] <= data_input; // initial data input for NoC

				else flit_data_output[port_num] <= 0; // clears data in all channels
			end
			
			else if(valid_output[port_num]) begin
				// needs some backpressure logic here
				// sends out data from cpu to physical channel
				flit_data_output[port_num] <= (node_needs_to_send_its_own_data[port_num]) ?
												node_own_data[port_num] : node_data_from_cpu;
			end

			else flit_data_output[port_num] <=0;
		end

	end

endgenerate

endmodule
