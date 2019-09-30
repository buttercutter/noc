// Credit : https://github.com/jbush001/NyuziProcessor/blob/master/hardware/core/sync_fifo.sv
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// First-in, first-out queue, with synchronous read/write
// - SIZE must be a power of two and greater than or equal to 4.
// - almost_full asserts when there are ALMOST_FULL_THRESHOLD or more entries
//   queued.
// - almost_empty asserts when there are ALMOST_EMPTY_THRESHOLD or fewer
//   entries queued.
// - almost_full is still asserted when full is asserted, as is almost_empty
//   when empty is asserted.
// - flush takes precedence over enqueue/dequeue if it is asserted
//   simultaneously. It is synchronous, unlike reset.
// - It is not legal to assert enqueue when the FIFO is full or dequeue when it
//   is empty (The former is true even if there is a dequeue and enqueue in the
//   same cycle, which wouldn't change the count). Doing this will trigger an
//   error in the simulator and have incorrect behavior in synthesis.
// - dequeue_value will contain the next value to be dequeued even if dequeue_en is
//   not asserted.
//

module sync_fifo
    #(parameter WIDTH = 4,
    parameter SIZE = 8
    //parameter ALMOST_FULL_THRESHOLD = SIZE,
    //parameter ALMOST_EMPTY_THRESHOLD = 1
	)

    (input                       clk,
    input                        reset,
    output		                 full,
    //output reg                 almost_full,
    input                        enqueue_en,
    input [WIDTH - 1:0]          enqueue_value,
    output		                 empty,
    //output reg                 almost_empty,
    input                        dequeue_en,
    output [WIDTH - 1:0]    	 dequeue_value);


    parameter ADDR_WIDTH = $clog2(SIZE);

	// read and write pointers need one extra MSB bit to differentiate between empty and full
	// you can confirm this using  count = wr_addr - rd_addr;

    reg[ADDR_WIDTH:0] rd_addr;
    reg[ADDR_WIDTH:0] wr_addr;

	reg[WIDTH - 1:0] data[SIZE - 1:0];


`ifdef FORMAL
	
	initial rd_addr = 0;
	initial wr_addr = 0;
`endif

	wire[ADDR_WIDTH:0] count = wr_addr - rd_addr;

    //assign almost_full = count >= (ADDR_WIDTH + 1)'(ALMOST_FULL_THRESHOLD);
    //assign almost_empty = count <= (ADDR_WIDTH + 1)'(ALMOST_EMPTY_THRESHOLD);

    assign full = (count == SIZE[ADDR_WIDTH:0]);
    assign empty = count == 0;
    assign dequeue_value = data[rd_addr[ADDR_WIDTH-1:0]]; // passed verilator width warning

	integer index;

    always @(posedge clk)
    begin
        if (reset)
        begin
            rd_addr <= 0;
            wr_addr <= 0;

			for(index=0; index<SIZE; index=index+1)
				data[index] <= 0;
        end

        else begin

			// https://twitter.com/zipcpu/status/1143134086950789120
			// if enqueue_en and dequeue_en and full at the same time, nothing is added, one item is removed,
			// but count is not modified. Same for empty.

			// https://zipcpu.com/blog/2017/07/29/fifo.html 
			// https://zipcpu.com/tutorial/lsn-10-fifo.pdf

			case( {(dequeue_en && !empty), (enqueue_en && !full) })
				
				'b00 : 	begin 
							wr_addr <= wr_addr;
							rd_addr <= rd_addr; 
						end

				'b01 : 	begin
							wr_addr <= wr_addr + 1;
							data[wr_addr[ADDR_WIDTH-1:0]] <= enqueue_value; // passed verilator width warning
							rd_addr <= rd_addr;
						end

				'b10 : 	begin
							wr_addr <= wr_addr;
							rd_addr <= rd_addr + 1;
						end

				'b11 : 	begin
							wr_addr <= wr_addr + 1;
							data[wr_addr[ADDR_WIDTH-1:0]] <= enqueue_value; // passed verilator width warning
							rd_addr <= rd_addr + 1;
						end

				default: begin
							wr_addr <= wr_addr;
							rd_addr <= rd_addr;
						 end
			endcase				
        end
    end


// All the following formal proofs are modified from https://github.com/promach/afifo/blob/master/async_fifo.sv
// and sfifo.v in http://zipcpu.com/tutorial/ex-10-fifo.zip

/*See https://zipcpu.com/blog/2018/07/06/afifo.html for a formal proof of afifo in general*/

`ifdef FORMAL

	reg first_clock_had_passed;

	initial first_clock_had_passed = 0;

	always @(posedge clk)
		first_clock_had_passed <= 1;	


	initial assume(reset);

	always @(posedge clk)
	begin
		if(first_clock_had_passed && $past(reset))
		begin
			assert(rd_addr == 0);
			assert(!full);

			assert(wr_addr == 0);
			assert(empty);
		end

		else if(first_clock_had_passed) 
		begin
 			assert(count == (wr_addr - rd_addr));
			assert(count <= SIZE);
    		assert(full == (count == SIZE));
    		assert(empty == (count == 0));
		end
	end

	always @(posedge clk)
	begin
		if (first_clock_had_passed)
		begin
			if($past(reset))
			begin
				assert(count == 0);
				assert(!full);	
				assert(empty);			
				assert(dequeue_value == 0);
			end						
		end
	end
`endif


`ifdef FORMAL

	////////////////////////////////////////////////////
	//
	// Some cover statements, to make sure valuable states
	// are even reachable
	//
	////////////////////////////////////////////////////
	//

	// Make sure a reset is possible
	always @(posedge clk)
		cover(reset);

	always @(posedge clk)
	if (first_clock_had_passed)
		cover((empty)&&(!$past(empty)));

	always @(*)
	if (first_clock_had_passed)
		cover(full);

	always @(posedge clk)
	if (first_clock_had_passed)
		cover($past(full)&&($past(enqueue_en))&&(full));

	always @(posedge clk)
	if (first_clock_had_passed)
		cover($past(full)&&(!full));

	always @(posedge clk)
		cover((full)&&(enqueue_en));

	always @(posedge clk)
		cover(enqueue_en);

	always @(posedge clk)
		cover((empty)&&(dequeue_en));

	always @(posedge clk)
	if (first_clock_had_passed)
		cover($past(!empty)&&($past(dequeue_en))&&(empty));
		
`endif
	
`ifdef FORMAL
	
	/* twin-write test */
	// write two pieces of different data into the synchronous fifo
	// then read them back from the synchronous fifo
	
	wire [WIDTH - 1:0] first_data = $anyconst;
	wire [WIDTH - 1:0] second_data = $anyconst;

	always @(*) assume(first_data != 0);
	always @(*) assume(second_data != 0);
	always @(*) assume(first_data != second_data);


	// for induction verification
	wire [ADDR_WIDTH : 0] f_first_addr = $anyconst;
	reg [ADDR_WIDTH : 0] f_second_addr;

	always @(*) f_second_addr <= f_first_addr + 1;

	wire	wr = (enqueue_en && !full);
	wire	rd = (dequeue_en && !empty);


	localparam IDLE = 0;
	localparam FIRST_DATA_IS_WRITTEN = 1;
	localparam SECOND_DATA_IS_WRITTEN = 2;
	localparam FIRST_DATA_IS_READ = 3;

	reg	[1:0]	f_state;
	initial	f_state = IDLE;

	// See http://zipcpu.com/tutorial/lsn-10-fifo.pdf#page=21 for understanding the state machine

	always @(posedge clk)
	begin
		if(reset) f_state <= IDLE;

		else begin

			case(f_state)
				IDLE: 

					if (wr && (wr_addr == f_first_addr) && (enqueue_value == first_data))
						// Wrote first value
						f_state <= FIRST_DATA_IS_WRITTEN;

				FIRST_DATA_IS_WRITTEN: 

					if (rd && rd_addr == f_first_addr)
						// Test sprung early
						f_state <= IDLE;

					else if (wr)
						f_state <= (enqueue_value == second_data) ? SECOND_DATA_IS_WRITTEN : IDLE;

				SECOND_DATA_IS_WRITTEN: 

					if (dequeue_en && rd_addr == f_first_addr)
						f_state <= FIRST_DATA_IS_READ;

				FIRST_DATA_IS_READ: 

					if (dequeue_en) // second data is read, thus goes back idling
						f_state <= IDLE;
			endcase
		end
	end


	reg	f_first_addr_in_fifo, f_second_addr_in_fifo;
	reg	[ADDR_WIDTH :0]	f_distance_to_first, f_distance_to_second;

	always @(*)
	begin
		f_distance_to_first <= (f_first_addr - rd_addr);
		f_first_addr_in_fifo <= 0;

		if ((count != 0) && (f_distance_to_first < count))
			f_first_addr_in_fifo <= 1;
		else
			f_first_addr_in_fifo <= 0;
	end

	always @(*)
	begin
		f_distance_to_second <= (f_second_addr - rd_addr);

		if ((count != 0) && (f_distance_to_second < count))
			f_second_addr_in_fifo <= 1;
		else
			f_second_addr_in_fifo <= 0;
	end


	always @(posedge clk)
	begin
		case(f_state)

			IDLE: 
			begin

			end

			FIRST_DATA_IS_WRITTEN: 
			begin
				assert(f_first_addr_in_fifo);
				assert(data[f_first_addr] == first_data);

				assert(wr_addr == f_second_addr);
			end

			SECOND_DATA_IS_WRITTEN: 
			begin
				assert(f_first_addr_in_fifo);
				assert(data[f_first_addr] == first_data);
				
				assert(f_second_addr_in_fifo);
				assert(data[f_second_addr] == second_data);

				if (dequeue_en && rd_addr == f_first_addr)
					assert(dequeue_value == first_data);
			end

			FIRST_DATA_IS_READ: 
			begin
				assert(f_second_addr_in_fifo);
				assert(data[f_second_addr] == second_data);

				assert(dequeue_value == second_data);
			end

		endcase
	end

`endif


endmodule