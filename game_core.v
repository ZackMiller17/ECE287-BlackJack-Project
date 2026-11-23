module game_core(
	input        clk,
	input        rst,             // active low
	output [5:0] rd_card,         // the card at that position: {suit, rank}
	output       deck_ready,      // 1 when the deck is built
	output reg   deck_shuffled,  // 1 after a shuffle finishes, 0 after a rebuild
	
	// Game Inputs / Outputs
	
	input deal,
	input hit,
	input stand,
	input double,
	output [5:0] player_val,       // best total of the player's hand
	output [5:0] dealer_val,       // best total of the dealer's hand
	output [5:0] game_state,
	output reveal,                 // 1 when the dealers hidden card should be shown
	output reg [2:0] result,  		// 0 none, 1 blackjack, 2 player win, 3 dealer win, 4 push, 5 player bust
	input [9:0] bet,          // Bet that the player makes
	output reg [11:0] bank,
	output reg [9:0] cur_bet,
	
	output not_allowed,
	output no_bet,
	
	
	
	// Hands for the VGA renderer
	output [35:0] p_hand,          // player's first 6 cards, 6 bits each, first card in [5:0]
	output [35:0] d_hand,          // dealer's first 6 cards
	output [3:0]  p_num,           // how many cards the player has
	output [3:0]  d_num            // how many cards the dealer has
);

//---------- wires connecting the shuffler to the deck -------------------
wire        swap_en;
wire [5:0]  swap_i;
wire [5:0]  swap_j;
wire        shuffle_done;
wire shuf_start;
reg  [5:0] deal_ptr;              // position of the next card to deal
wire [5:0] rd_idx = deal_ptr;     // the deck shows us the card at deal_ptr

// instantiate the deck /
deck the_deck(
	.clk(clk),
	.rst(rst),
	.build(1'b0),
	.ready(deck_ready),
	.swap_en(swap_en),
	.swap_i(swap_i),
	.swap_j(swap_j),
	.rd_idx(rd_idx),
	.rd_card(rd_card)
);

// instantiate the shuffler -------
shuffler the_shuffler(
	.clk(clk),
	.rst(rst),
	.start(shuf_start),
	.deck_ready(deck_ready),
	.swap_en(swap_en),
	.swap_i(swap_i),
	.swap_j(swap_j),
	.done(shuffle_done)
);

// --------Shuffling the deck--------

always @(posedge clk or negedge rst)
begin
	if (rst == 1'b0)
		deck_shuffled <= 1'b0;
	else if (shuffle_done == 1'b1)
		deck_shuffled <= 1'b1;
end

//---------------------------------


// ---------- the two hands ---------- 
reg [5:0] p_card [0:7];   // player's cards, slot 0 = first card dealt
reg [5:0] d_card [0:7];   // dealer's cards
reg [3:0]  p_count;     // how many cards each hand has
reg [3:0]  d_count;
reg [5:0]  p_sum;       // total counting every Ace as 1
reg [5:0]  d_sum;
reg [2:0]  p_aces;      // how many Aces each hand has
reg [2:0]  d_aces;

// pack the first 6 slots of each hand into one bus for the renderer
assign p_hand = {p_card[5], p_card[4], p_card[3], p_card[2], p_card[1], p_card[0]};
assign d_hand = {d_card[5], d_card[4], d_card[3], d_card[2], d_card[1], d_card[0]};
assign p_num  = p_count;
assign d_num  = d_count;

// -------- Value of the current card that is being dealt ------------

wire [3:0] c_rank   = rd_card[3:0];
wire [5:0] c_pts    = (c_rank >= 4'd10) ? 6'd10 : {2'b00, c_rank};   // J, Q, K = 10
wire       c_is_ace = (c_rank == 4'd1);

// ---------- best total of each hand (Ace can count as 11) ----------
wire p_has_ace  = (p_aces > 3'd0);        // the player has at least one Ace
wire d_has_ace  = (d_aces > 3'd0);

wire p_has_room = (p_sum < 6'd12);        // adding 10 would still be 21 or less
wire d_has_room = (d_sum < 6'd12);

assign player_val = (p_has_ace && p_has_room) ? (p_sum + 6'd10) : p_sum;
assign dealer_val = (d_has_ace && d_has_room) ? (d_sum + 6'd10) : d_sum;


// ---------------- DEAL DELAY -----------------------------

reg [24:0] deal_counter;
reg dealer_card_taken;
wire deal_delay_done = (deal_counter == 25'd19999999);



always @(negedge clk or negedge rst) begin
    if (!rst) begin
        deal_counter <= 25'd0;
    end
    else begin
        if (S == DEAL_C || S == HIT ||
            S == DOUBLE || S == DEALER_HIT) begin

            if (deal_delay_done)
                deal_counter <= 25'd0;
            else
                deal_counter <= deal_counter + 1'b1;

        end
        else begin
            deal_counter <= 25'd0;
        end
    end
end




//-----------------------------------------------------------



// ----- BlackJack FSM --------------

reg [5:0]S;
reg [5:0]NS;

assign game_state = S;

reg [4:0]c_in_play;			// number of cards in play during each round
reg       doubled;        // 1 if the player doubled down this round
reg       shuffling;      // 1 while the shuffler is working

assign not_allowed = (bet > bank);
assign no_bet = (bet == 1'b0);



// States

parameter START = 6'd0,
			DEAL_C = 6'd1,
			BLACKJACK = 6'd2,
			DECISION = 6'd3,
			BUST = 6'd4,
			DOUBLE = 6'd5,
			HIT = 6'd6,
			DEALER_DEC = 6'd7,
			WIN_CHK = 6'd8,
			DEALER_HIT = 6'd9,
			PLAYER_WIN = 6'd10,
			DEALER_WIN = 6'd11,
			PUSH = 6'd12,
			PLAY_AGAIN = 6'd13,
			SHUFFLE = 6'd14,
			SHUFFLE_WAIT = 6'd15;
			

// a deal request is only accepted when the deck is built and not being shuffled
wire deal_ok = (deal == 1'b1 && deck_ready == 1'b1 && shuffling == 1'b0 && bet != 10'd0 && bet <= bank);

// the shuffler is started only by the SHUFFLE state (once at the start of every round)
assign shuf_start = (S == SHUFFLE);

// the dealer's second card is face down until the player is done
assign reveal = !(S == DEAL_C || S == DECISION || S == HIT || S == DOUBLE);


// remembers that the shuffler is busy
always @(posedge clk or negedge rst) begin
	if (rst == 1'b0) begin
		shuffling <= 1'b0;
	end
	else if (shuf_start == 1'b1 && deck_ready == 1'b1) begin
		shuffling <= 1'b1;
	end
	else if (shuffle_done == 1'b1) begin
		shuffling <= 1'b0;
	end
end			
			
			


// state register
always @ (posedge clk or negedge rst) begin

if( rst == 1'b0)

	S <= START;
	
else

	S <= NS;
	
end



// Next state logic


always@(*) begin

	NS = S;

	case(S)
	
			//-------------------------------

		START: begin

			if (deal_ok == 1'b1)
				NS = SHUFFLE;
			else
				NS = START;

		end
		 // ------------------------------	
			
DEAL_C: begin

			// still handing out the opening four cards
			if (c_in_play < 5'd4)
				NS = DEAL_C;

				
			// all four cards are out check for a natural 21 first
			else if (player_val == 6'd21 && dealer_val == 6'd21)
				NS = PUSH;
				
			else if (player_val == 6'd21)
				NS = BLACKJACK;
				
			else if (dealer_val == 6'd21)
				NS = DEALER_WIN;
				
			else
				NS = DECISION;

		end
		//--------------------------------
			
			BLACKJACK:  NS = PLAY_AGAIN;
			
		//--------------------------------
			
			DECISION: begin
			
				// --- player selects hit -----
				if (hit == 1'b1) begin
				
					NS = HIT;
				end
				
				// --- player selects stand ----
				else if ( stand == 1'b1) begin
				
					NS = DEALER_DEC;
				end
				
				//--- player seclects double, and checks to see if they are allowed ----
				else if ( (double == 1'b1) && (p_count == 4'd2) && bank >= cur_bet) begin
				
					NS = DOUBLE;
					
				end
				
				else begin
				
					NS = DECISION;
				
				end
			
			end
		//--------------------------------
			
			BUST: NS = PLAY_AGAIN;

		//----------------------------------
			
			DOUBLE: begin

			if (player_val > 6'd21)
				NS = BUST;
			else
				NS = DEALER_DEC;

		end
		//---------------------------------
			
			HIT: begin

			if (player_val > 6'd21)
				NS = BUST;
				
			else if (player_val == 6'd21)      // 21 can't be improved, so stand automatically
				NS = DEALER_DEC;
				
			else
				NS = DECISION;

		end
		//---------------------------------
			
			DEALER_DEC: begin

			if (dealer_val < 6'd17)
				NS = DEALER_HIT;
				
			else
				NS = WIN_CHK;

		end
		//---------------------------------
			
			WIN_CHK: begin

			if (dealer_val > 6'd21)
				NS = PLAYER_WIN;
				
			else if (player_val > dealer_val)
				NS = PLAYER_WIN;
				
			else if (dealer_val > player_val)
				NS = DEALER_WIN;
				
			else
				NS = PUSH;

		end
			
		//---------------------------------
			
			DEALER_HIT: begin

				if (dealer_card_taken == 1'b1)
					NS = DEALER_DEC;
				else
					NS = DEALER_HIT;

			end
			
		//----------------------------------
			
			PLAYER_WIN: NS = PLAY_AGAIN;
			
		//-----------------------------------
			
			DEALER_WIN: NS = PLAY_AGAIN;
			
		//-----------------------------------
			
			PUSH: NS = PLAY_AGAIN;
			
		//-----------------------------------
			PLAY_AGAIN: begin

			// next round requested: shuffle first
			if (deal_ok == 1'b1)
				NS = SHUFFLE;
			else
				NS = PLAY_AGAIN;

		end
			
		//-------------------------------

		SHUFFLE: NS = SHUFFLE_WAIT;

		SHUFFLE_WAIT: begin

			if (shuffling == 1'b0)
				NS = DEAL_C;
			else
				NS = SHUFFLE_WAIT;

		end

		//-------------------------------
		
			default: NS = START;
	endcase
end
		
// State logic
		
always@(negedge clk or negedge rst) begin

if (rst == 1'b0) begin
		deal_ptr  <= 6'd0;
		c_in_play <= 5'd0;
		p_sum     <= 6'd0;
		d_sum     <= 6'd0;
		p_aces    <= 3'd0;
		d_aces    <= 3'd0;
		p_count   <= 4'd0;
		d_count   <= 4'd0;
		doubled   <= 1'b0;
		result    <= 3'd0;
		bank      <= 12'd200;
		cur_bet   <= 10'd0;
		dealer_card_taken <= 1'b0;
	end
	
else begin

	case(S)
	
			//-------------------------------

			START: begin	
			
			cur_bet <= bet;
			
			end
		 // ------------------------------	
			
			// the opening deal, deals 4 cards
			DEAL_C: begin
			if (deal_delay_done) begin
			
				if(c_in_play == 5'd1) begin
				
					bank <= bank - cur_bet;
				end

				if (c_in_play < 5'd4) begin

					// first and third card goes to the player
					if (c_in_play == 5'd0 || c_in_play == 5'd2) begin

						p_sum   <= p_sum + c_pts;
						p_count <= p_count + 4'd1;
						p_card[p_count] <= rd_card;

						if (c_is_ace == 1'b1) begin
							p_aces <= p_aces + 3'd1;
						end
					end

					// second and fourth card goes to the dealer
					else begin

						d_sum   <= d_sum + c_pts;
						d_count <= d_count + 4'd1;
						d_card[d_count] <= rd_card;

						if (c_is_ace == 1'b1) begin
							d_aces <= d_aces + 3'd1;
						end
					end

					deal_ptr  <= deal_ptr + 6'd1;    // moves to the next card in the deck
					c_in_play <= c_in_play + 5'd1;   // adds one more to the number of cards dealt

				end

			end
		end
		//--------------------------------
			BLACKJACK: begin

				result <= 3'd1;
				bank <= bank + (cur_bet << 1) + (cur_bet >> 1);   // 2.5 * bet

			end
		//--------------------------------
			
			DECISION: begin
			
			end
		//--------------------------------
			
			BUST: begin

				result <= 3'd5;
				bank <= bank;

			end
		//----------------------------------
			
		// player doubles, deals exactly one more card, then the player must stand
			DOUBLE: begin


				doubled <= 1'b1;
				
				bank <= bank - cur_bet;

				p_sum     <= p_sum + c_pts;
				p_count   <= p_count + 4'd1;
				p_card[p_count] <= rd_card;
				deal_ptr  <= deal_ptr + 6'd1;
				c_in_play <= c_in_play + 5'd1;

				if (c_is_ace == 1'b1) begin
					p_aces <= p_aces + 3'd1;
				end

			end

		//---------------------------------
			
			// player hits: one more card for the player
			HIT: begin


				p_sum     <= p_sum + c_pts;
				p_count   <= p_count + 4'd1;
				p_card[p_count] <= rd_card;
				deal_ptr  <= deal_ptr + 6'd1;
				c_in_play <= c_in_play + 5'd1;

				if (c_is_ace == 1'b1) begin
					p_aces <= p_aces + 3'd1;
				end

			end

		//---------------------------------
			
			DEALER_DEC: begin

				dealer_card_taken <= 1'b0;

			end
		//---------------------------------
			
			WIN_CHK: begin
			
			end
			
		//---------------------------------
			
			// dealer hits, gives one more card to the dealer
			DEALER_HIT: begin
			if (deal_delay_done) begin

				d_sum     <= d_sum + c_pts;
				d_count   <= d_count + 4'd1;
				d_card[d_count] <= rd_card;
				deal_ptr  <= deal_ptr + 6'd1;
				c_in_play <= c_in_play + 5'd1;
				dealer_card_taken <= 1'b1;

				if (c_is_ace == 1'b1) begin
					d_aces <= d_aces + 3'd1;
				end

			end
		end
			
		//----------------------------------
			
			PLAYER_WIN: begin

				result <= 3'd2;
				
				if (doubled == 1'b1) begin
				
					bank <= bank + ((5'd4)*cur_bet);
				
				end
				
				else begin
				
					bank <= bank + ((5'd2)*cur_bet);
				
				end

			end
		//-----------------------------------
			
			DEALER_WIN: begin

				result <= 3'd3;

			end
		//-----------------------------------
			
			PUSH: begin

				result <= 3'd4;
				
				if (doubled == 1'b1) begin
				
					bank <= bank + ((5'd2)*cur_bet);
				
				end
				
				else begin
				
					bank <= bank + cur_bet;
				
				end

			end
			
		//-----------------------------------
			PLAY_AGAIN: begin
			
				cur_bet <= bet;
			
			end
			
	//-----------------------------------

			// clear everything for the new round (runs once, right before the shuffle)
			SHUFFLE: begin
			
				cur_bet <= bet;

				c_in_play <= 5'd0;
				p_sum     <= 6'd0;
				d_sum     <= 6'd0;
				p_aces    <= 3'd0;
				d_aces    <= 3'd0;
				p_count   <= 4'd0;
				d_count   <= 4'd0;
				doubled   <= 1'b0;
				result    <= 3'd0;

			end

		//-----------------------------------

			SHUFFLE_WAIT: begin

			end

		//-----------------------------------

			default: begin

			end

		
	endcase
	
// ---- Reseting the deal pointer if the deck was shuffled ------------
	
	if (shuffle_done == 1'b1) begin
			deal_ptr <= 6'd0;
		end
end

end


endmodule