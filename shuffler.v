module shuffler(
    input        clk,
    input        rst,          // active low
    input        start,        // 1-clock pulse: begin a shuffle
    input        deck_ready,   // connect to deck's "ready" output
    output reg   swap_en,      // to deck: swap this clock
    output reg [5:0] swap_i,   // to deck
    output reg [5:0] swap_j,   // to deck
    output       done          // 1-clock pulse when shuffle is finished
);

// LFSR
reg [15:0] lfsr;

always @(posedge clk or negedge rst)
begin
	if (rst == 1'b0)
		lfsr <= 16'hACE1;
	else
		lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
end

wire [5:0] cand = lfsr[5:0];   // candidate value for j (0 through 63)

// FSM signals and parameters
reg [2:0] S;
reg [2:0] NS;
parameter START = 3'd0,   // waiting for start
          PICK  = 3'd1,   // trying to find a valid j
          SWAP  = 3'd2,   // swap_en is high during this state
          DONE  = 3'd3,   // one-cycle "done" state
          ERROR = 3'd4;

// the position being fixed, 51 down to 1
reg [5:0] i;

assign done = (S == DONE);

// S update always block
always @(posedge clk or negedge rst)
begin
	if (rst == 1'b0)
		S <= START;
	else
		S <= NS;
end

// NS transitions always block 
always @(*)
begin
	case (S)
		START: if (start == 1'b1 && deck_ready == 1'b1)
					NS = PICK;
				 else
					NS = START;

		PICK:  if (cand <= i)          // accepted: cand is in [0, i]
					NS = SWAP;
				 else
					NS = PICK;          // rejected: try the next LFSR value

		SWAP:  if (i == 6'd1)          // i = 1 was the last swap
					NS = DONE;
				 else
					NS = PICK;

		DONE:  NS = START;

		default: NS = ERROR;
	endcase
end

// clocked control signals always block
always @(posedge clk or negedge rst)
begin
	if (rst == 1'b0)
	begin
		swap_en <= 1'b0;
		swap_i  <= 6'd0;
		swap_j  <= 6'd0;
		i       <= 6'd51;
	end
	else
	begin
		case (S)
			START: begin
				swap_en <= 1'b0;
				i       <= 6'd51;      // reload the top position, ready for the next shuffle
			end

			PICK: begin
				if (cand <= i)          // same condition the NS block uses
				begin
					swap_i  <= i;
					swap_j  <= cand;
					swap_en <= 1'b1;    // becomes 1 as we enter SWAP
				end
			end

			SWAP: begin
				swap_en <= 1'b0;        // swap_en was high for exactly this one state
				if (i != 6'd1)
					i <= i - 6'd1;
			end
		endcase
	end
end

endmodule