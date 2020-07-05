module NoC 
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
(clk, reset, done);

input clk, reset;
output done;

reg  [NUM_OF_NODES*FLIT_TOTAL_WIDTH-1:0] data_input;
wire [FLIT_DATA_WIDTH-1:0] data_output;

assign done = (data_output == 1); // just to avoid EDA tool optimizes away NoC design logic

localparam HEAD_TAIL = 2;
localparam FLIT_TOTAL_WIDTH = HEAD_TAIL+$clog2(NUM_OF_VIRTUAL_CHANNELS)+FLIT_DATA_WIDTH;

// the most significant two bits are to indicate head and/or tail flits,
// followed by dest_node and flit_data_payload
// See http://www.lisnoc.org/packets.html

// 01 = head_flit , 10 = data_flit (body_flit), 00 = tail_flit, 11 = flit_without_data_payload
localparam HEAD_FLIT = 2'b01;
localparam HEADER = 2'b11; // flit_without_data_payload
localparam BODY_FLIT = 2'b10;
localparam TAIL_FLIT = 2'b00;

parameter DEST_NODE_WIDTH = $clog2(NUM_OF_NODES);

spidergon_top 
#(
    .NUM_OF_NODES(NUM_OF_NODES), 
    .FLIT_DATA_WIDTH(FLIT_DATA_WIDTH), 
    .NODE_BUFFER_WIDTH(NODE_BUFFER_WIDTH),
    .NUM_OF_VIRTUAL_CHANNELS(NUM_OF_VIRTUAL_CHANNELS)
)
sp(.clk(clk), .reset(reset), .data_input(data_input), .data_output(data_output));



//`define ONE_NODE_SENDING 1
//`define TWO_NODES_SENDING 1
//`define FOUR_NODES_SENDING 1
`define ALL_NODES_SENDING 1

generate
    genvar node_num;

    for(node_num = 0; node_num < NUM_OF_NODES; node_num = node_num + 1)
    begin : DATA_INPUT
	 
    	`ifdef ONE_NODE_SENDING
    	
		    always@(posedge clk)
		    begin
				if(reset)
				begin
					if(node_num == 1) // send data from node 1 to node 0
					begin
					    data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH] <= 
			               {
								HEADER, 
								{$clog2(NUM_OF_VIRTUAL_CHANNELS){1'b0}}, // assume the first VC
		 				 		node_num[DEST_NODE_WIDTH-1:0], // destination node address
		 				 		node_num[DEST_NODE_WIDTH-1:0]+{DEST_NODE_WIDTH{1'b1}}, // source node address
					 			{(FLIT_TOTAL_WIDTH-HEAD_TAIL-$clog2(NUM_OF_VIRTUAL_CHANNELS)-
								 DEST_NODE_WIDTH-DEST_NODE_WIDTH){1'b0}}
							};
					end 
					                
					else data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH] <= 
					                {TAIL_FLIT, {FLIT_DATA_WIDTH{1'b0}}};    
				end

				else data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH] <= 0;
		    end
		     		    	
    	`endif
  
    	`ifdef TWO_NODES_SENDING
    	
			// send data from nodes 1,2 to node 0, 
			// to verify virtual channel reservation logic 
			// given that both nodes 1 and 2 need to compete for virtual channels 
			// at the same port (clockwise)
    	
		    always@(posedge clk)
		    begin
				if(reset)
				begin
					if((node_num == 1) || (node_num == 2))
					begin
					    data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH] <= 
			               {
								HEADER, 
								{$clog2(NUM_OF_VIRTUAL_CHANNELS){1'b0}}, // assume the first VC
		 				 		node_num[DEST_NODE_WIDTH-1:0], // destination node address
		 				 		node_num[DEST_NODE_WIDTH-1:0]+{DEST_NODE_WIDTH{1'b1}}, // source node address
					 			{(FLIT_TOTAL_WIDTH-HEAD_TAIL-$clog2(NUM_OF_VIRTUAL_CHANNELS)-
								 DEST_NODE_WIDTH-DEST_NODE_WIDTH){1'b0}}
							};
					end 
					                
					else data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH] <= 
					                {TAIL_FLIT, {FLIT_DATA_WIDTH{1'b0}}}; 
				end

				else data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH] <= 0;   
		    end
		     		    	
    	`endif

    	`ifdef FOUR_NODES_SENDING
    	
			// send data from nodes 1,2 (clockwise) and 6,7 (anti-clockwise) to node 0, 
			// to verify virtual channel reservation logic 
			// given that both nodes 1 and 2 need to compete for virtual channels 
			// at the same port (clockwise)
			// Same competition for both nodes 6 and 7
    	
		    always@(posedge clk)
		    begin
				if(reset)
				begin
					if((node_num == 1) || (node_num == 2) || (node_num == 6) || (node_num == 7))
					begin
					    data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH] <= 
			               {
								HEADER, 
								{$clog2(NUM_OF_VIRTUAL_CHANNELS){1'b0}}, // assume the first VC
		 				 		node_num[DEST_NODE_WIDTH-1:0], // destination node address
		 				 		node_num[DEST_NODE_WIDTH-1:0]+{DEST_NODE_WIDTH{1'b1}}, // source node address
					 			{(FLIT_TOTAL_WIDTH-HEAD_TAIL-$clog2(NUM_OF_VIRTUAL_CHANNELS)-
								 DEST_NODE_WIDTH-DEST_NODE_WIDTH){1'b0}}
							};	
					end 
					                
					else data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH] <= 
					                {TAIL_FLIT, {FLIT_DATA_WIDTH{1'b0}}}; 
				end

				else data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH] <= 0;   
		    end
		     		    	
    	`endif

    	`ifdef ALL_NODES_SENDING // send data in circular loop and clockwise manner to check for deadlock
    	
		    always@(posedge clk)
			begin
		        if(reset) 
		        begin
		        	data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH] <= 
					{
						HEADER, 
						{$clog2(NUM_OF_VIRTUAL_CHANNELS){1'b0}}, // assume the first VC
						node_num[DEST_NODE_WIDTH-1:0]+{{(DEST_NODE_WIDTH-1){1'b0}}, 1'b1}, // dest node address
						node_num[DEST_NODE_WIDTH-1:0], // source node address
						{(FLIT_TOTAL_WIDTH-HEAD_TAIL-$clog2(NUM_OF_VIRTUAL_CHANNELS)-
						 DEST_NODE_WIDTH-DEST_NODE_WIDTH){1'b0}}
					};	
				end
				
				else data_input[node_num*FLIT_TOTAL_WIDTH +: FLIT_TOTAL_WIDTH] <= 0;
			end
		`endif
    end
endgenerate

endmodule
