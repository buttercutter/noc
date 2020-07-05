module test_spidergon
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
);


reg clk, reset;


  // Instantiate design under test
  NoC 
  #(
        .NUM_OF_NODES(NUM_OF_NODES), 
        .FLIT_DATA_WIDTH(FLIT_DATA_WIDTH), 
        .NODE_BUFFER_WIDTH(NODE_BUFFER_WIDTH),
        .NUM_OF_VIRTUAL_CHANNELS(NUM_OF_VIRTUAL_CHANNELS)
  )
  noc(.clk(clk), .reset(reset));
  
  
  initial begin
    // Dump waves
    $dumpfile("spidergon.vcd");
    $dumpvars(0, test_spidergon);
    
    clk = 0;
    reset = 0;

  end


  always #5 clk = !clk;
 
  initial begin
    
    @(posedge clk);

	@(posedge clk);

    $display("Reset flop.");

    reset = 1;

    @(posedge clk);
	@(posedge clk);  // reset is extended for one more clock cycle

    reset = 0;

    @(posedge clk);

    #300 $finish;

  end

endmodule
