module deck(
	input clk,
	input rst,              // active low reset
	input build,              // 1-clock pulse: rebuild the deck in order
	output ready,             // 1 when the deck is built and can be used
	input swap_en,            // 1 = swap positions swap_i and swap_j this clock
	input [5:0] swap_i,
	input [5:0] swap_j,
	input [5:0] rd_idx,       // position to look at (0..51)
	output [5:0] rd_card      // the card at that position: {suit, rank}
);

reg [5:0] mem [0:51];         // the 52 cards, 6 bits each

reg [5:0] k;                  // position being written during the build
reg [3:0] rank;               // 1..13   (1 = Ace, 11 = J, 12 = Q, 13 = K)
reg [1:0] suit;               // 0 hearts, 1 diamonds, 2 spades, 3 clubs
reg built;

assign ready   = built;
assign rd_card = mem[rd_idx];

always @(posedge clk or negedge rst)
begin
	if (rst == 1'b0)                    // real reset
	begin
		k     <= 6'd0;
		rank  <= 4'd1;
		suit  <= 2'd0;
		built <= 1'b0;
	end
	else if (build)                     // rebuild request: start over (same values)
	begin
		k     <= 6'd0;
		rank  <= 4'd1;
		suit  <= 2'd0;
		built <= 1'b0;
	end
	else if (built == 1'b0) begin       // still building: one card per clock
		mem[k] <= {suit, rank};

		if (rank == 4'd13) begin
			rank <= 4'd1;
			suit <= suit + 2'd1;
		end
		else
			rank <= rank + 4'd1;

		if (k == 6'd51)
			built <= 1'b1;
		else
			k <= k + 6'd1;
	end
	else if (swap_en)                   // built: allow swaps
	begin
		mem[swap_i] <= mem[swap_j];
		mem[swap_j] <= mem[swap_i];
	end
end
endmodule