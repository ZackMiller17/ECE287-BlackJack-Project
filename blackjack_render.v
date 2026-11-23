module blackjack_render (
    input [9:0] x,
    input [9:0] y,
    input video_on,
    input [35:0] p_hand,      // player's cards, 6 bits each, first card in [5:0]
    input [35:0] d_hand,      // dealer's cards
    input [3:0] p_num,        // how many cards the player has
    input [3:0] d_num,        // how many cards the dealer has
    input reveal,             // 1 = dealer's second card face up, 0 = face down
	 input [9:0] bet,
	 input [11:0] bank,
	 input [5:0] game_state,
	 input [2:0] result,
	 input not_allowed,
	 input no_bet,
    output reg [7:0] VGA_R,
    output reg [7:0] VGA_G,
    output reg [7:0] VGA_B
	 
	 
	 
);

    // Row positions and pixel sizes
    parameter DEALER_Y = 10'd60,
              PLAYER_Y = 10'd310,
              RANK_SCALE = 3,
              SUIT_SCALE = 4;

    // Left edge of each of the 6 card slots (cards are 75 wide, 15 pixel gap)
    parameter X0 = 10'd60,
              X1 = 10'd150,
              X2 = 10'd240,
              X3 = 10'd330,
              X4 = 10'd420,
              X5 = 10'd510;

    // ---- Determining if the card should go in the dealer or player row ----
    reg in_row;               // pixel is inside one of the two card rows
    reg is_dealer;            // 1 = dealer row, 0 = player row
    reg [9:0] local_y;        // y position inside the card

    always @(*) begin
        in_row    = 1'b0;
        is_dealer = 1'b0;
        local_y   = 10'd0;

        if (y >= DEALER_Y && y < DEALER_Y + 110) begin
            in_row    = 1'b1;
            is_dealer = 1'b1;
            local_y   = y - DEALER_Y;
        end
        else if (y >= PLAYER_Y && y < PLAYER_Y + 110) begin
            in_row    = 1'b1;
            is_dealer = 1'b0;
            local_y   = y - PLAYER_Y;
        end
    end

    // ---- Determining which card slot the card will go in ----
    reg in_slot;              // pixel is inside one of the 6 card columns
    reg [2:0] slot;           // 0 to 5, left to right
    reg [9:0] local_x;        // x position inside the card

    always @(*) begin
        in_slot = 1'b1;
        slot    = 3'd0;
        local_x = 10'd0;

        if (x >= X0 && x < X0 + 75) begin
            slot    = 3'd0;
            local_x = x - X0;
        end
        else if (x >= X1 && x < X1 + 75) begin
            slot    = 3'd1;
            local_x = x - X1;
        end
        else if (x >= X2 && x < X2 + 75) begin
            slot    = 3'd2;
            local_x = x - X2;
        end
        else if (x >= X3 && x < X3 + 75) begin
            slot    = 3'd3;
            local_x = x - X3;
        end
        else if (x >= X4 && x < X4 + 75) begin
            slot    = 3'd4;
            local_x = x - X4;
        end
        else if (x >= X5 && x < X5 + 75) begin
            slot    = 3'd5;
            local_x = x - X5;
        end
        else begin
            in_slot = 1'b0;
        end
    end

    // ----  grab the card for this slot and decide if it should be drawn ----
    reg [5:0] card;           // {suit, rank} of the card under this pixel

    always @(*) begin
        case (slot)
            3'd0: card = is_dealer ? d_hand[5:0]   : p_hand[5:0];
            3'd1: card = is_dealer ? d_hand[11:6]  : p_hand[11:6];
            3'd2: card = is_dealer ? d_hand[17:12] : p_hand[17:12];
            3'd3: card = is_dealer ? d_hand[23:18] : p_hand[23:18];
            3'd4: card = is_dealer ? d_hand[29:24] : p_hand[29:24];
            3'd5: card = is_dealer ? d_hand[35:30] : p_hand[35:30];
            default: card = 6'd0;
        endcase
    end

    wire [3:0] card_rank = card[3:0];
    wire [1:0] card_suit = card[5:4];

    // the slot only shows a card once that many cards have been dealt
    wire [3:0] num = is_dealer ? d_num : p_num;
    wire card_pixel = in_row && in_slot && (slot < num);

    // the dealer's second card stays face down until reveal goes high
    wire face_down = card_pixel && is_dealer && (slot == 3'd1) && (reveal == 1'b0);

    // ---- Rank and suit drawing (same logic as before) ----
    wire rank_pixel;
    wire suit_pixel;
    reg rank_pixel_r;
    reg suit_pixel_r;
    reg [2:0] rank_px;
    reg [2:0] rank_py;
    reg [2:0] suit_px;
    reg [3:0] suit_py;

    // Rank glyph: 5x7 bitmap, enlarged 3x. Rank 10 uses a custom 1 + zero.
    always @(*) begin
        rank_pixel_r = 1'b0;
        rank_px = 3'd0;
        rank_py = 3'd0;
        if (card_rank == 4'd10) begin
            // Narrow '1' followed by the zero bitmap (character code 10)
            if ((local_x >= 7 && local_x < 10) && (local_y >= 6 && local_y < 27))
                rank_pixel_r = (local_x >= 8) || (local_y < 12);
            else if (local_x >= 12 && local_x < 27 && local_y >= 6 && local_y < 27) begin
                rank_px = (local_x - 12) / RANK_SCALE;
                rank_py = (local_y - 6) / RANK_SCALE;
                rank_pixel_r = draw_character(4'd10, rank_px, rank_py);
            end
        end else if (local_x >= 6 && local_x < 21 && local_y >= 6 && local_y < 27) begin
            rank_px = (local_x - 6) / RANK_SCALE;
            rank_py = (local_y - 6) / RANK_SCALE;
            rank_pixel_r = draw_character(card_rank, rank_px, rank_py);
        end
    end
    assign rank_pixel = rank_pixel_r;

    // Suit bitmap: 8x8 enlarged 4x and centered in the card.
    always @(*) begin
        suit_pixel_r = 1'b0;
        suit_px = 3'd0;
        suit_py = 4'd0;
        if (local_x >= 21 && local_x < 53 && local_y >= 39 && local_y < 71) begin
            suit_px = (local_x - 21) / SUIT_SCALE;
            suit_py = (local_y - 39) / SUIT_SCALE;
            suit_pixel_r = draw_suit_pixel(card_suit, suit_px, suit_py);
        end
    end
    assign suit_pixel = suit_pixel_r;
	 
function [3:0] display_digit;
    input [3:0] digit;

    begin
        if (digit == 4'd0)
            display_digit = 4'd10;
        else if (digit == 4'd1)
            display_digit = 4'd14;
			else 
				display_digit = digit;
    end
endfunction

function draw_suit_pixel;
    input [1:0] suit;
    input [2:0] px;
    input [3:0] py;

    reg [7:0] row_bits;

    begin
        row_bits = 8'b00000000;

        case (suit)

            // HEARTS
            2'b00:
                case (py)
                    0: row_bits = 8'b01101100;
                    1: row_bits = 8'b11111110;
                    2: row_bits = 8'b11111110;
                    3: row_bits = 8'b11111110;
                    4: row_bits = 8'b01111100;
                    5: row_bits = 8'b00111000;
                    6: row_bits = 8'b00010000;
                    default: row_bits = 0;
                endcase

            // DIAMONDS
            2'b01:
                case (py)
                    0: row_bits = 8'b00010000;
                    1: row_bits = 8'b00111000;
                    2: row_bits = 8'b01111100;
                    3: row_bits = 8'b11111110;
                    4: row_bits = 8'b01111100;
                    5: row_bits = 8'b00111000;
                    6: row_bits = 8'b00010000;
                    default: row_bits = 0;
                endcase

            // SPADES
            2'b10:
                case (py)
                    0: row_bits = 8'b00010000;
                    1: row_bits = 8'b00111000;
                    2: row_bits = 8'b01111100;
                    3: row_bits = 8'b11111110;
                    4: row_bits = 8'b11111110;
                    5: row_bits = 8'b01101100;
                    6: row_bits = 8'b00010000;
                    7: row_bits = 8'b00111000;
                    default: row_bits = 0;
                endcase

            // CLUBS
            2'b11:
                case (py)
                    0: row_bits = 8'b00010000;
                    1: row_bits = 8'b00111000;
                    2: row_bits = 8'b00111000;
                    3: row_bits = 8'b11010110;
                    4: row_bits = 8'b11111110;
                    5: row_bits = 8'b01101100;
                    6: row_bits = 8'b00010000;
                    7: row_bits = 8'b00111000;
                    default: row_bits = 0;
                endcase

        endcase

        draw_suit_pixel = row_bits[7 - px];
    end
endfunction

function draw_character;
    input [5:0] character;
    input [2:0] char_x;
    input [2:0] char_y;

    begin
        draw_character = 1'b0;

        case (character)

            // ACE (A)
            1: begin
                case (char_y)
                    0: draw_character = (char_x == 2);
                    1: draw_character = (char_x == 1 || char_x == 3);
                    2: draw_character = (char_x == 0 || char_x == 4);
                    3: draw_character = (char_x == 0 || char_x == 1 ||
                                         char_x == 2 || char_x == 3 ||
                                         char_x == 4);
                    4,5,6: draw_character = (char_x == 0 || char_x == 4);
                endcase
            end
				
				// 1 
				14: begin 
					 case (char_y)
						0,1,2,3,4,5,6:
							draw_character = (char_x == 2);
					endcase
			end		

            // 2
            2: begin
                case (char_y)
                    0: draw_character = (char_x >= 1 && char_x <= 3);
                    1,2: draw_character = (char_x == 4);
                    3: draw_character = (char_x >= 1 && char_x <= 3);
                    4,5: draw_character = (char_x == 0);
                    6: draw_character = (char_x >= 1 && char_x <= 3);
                endcase
            end

            // 3
            3: begin
                case (char_y)
                    0,3,6: draw_character = (char_x >= 1 && char_x <= 4);
                    1,2,4,5: draw_character = (char_x == 4);
                endcase
            end

            // 4
            4: begin
                case (char_y)
                    0,1,2: draw_character = (char_x == 0 || char_x == 4);
                    3: draw_character = 1'b1;
                    4,5,6: draw_character = (char_x == 4);
                endcase
            end

            // 5
            5: begin
                case (char_y)
                    0: draw_character = (char_x <= 4);
                    1,2: draw_character = (char_x == 0);
                    3: draw_character = (char_x >= 1 && char_x <= 4);
                    4,5: draw_character = (char_x == 4);
                    6: draw_character = (char_x <= 3);
                endcase
            end

            // 6
            6: begin
                case (char_y)
                    0: draw_character = (char_x >= 1 && char_x <= 3);
                    1,2: draw_character = (char_x == 0);
                    3: draw_character = (char_x >= 1 && char_x <= 3);
                    4,5: draw_character = (char_x == 0 || char_x == 4);
                    6: draw_character = (char_x >= 1 && char_x <= 3);
                endcase
            end

            // 7
            7: begin
                case (char_y)
                    0: draw_character = 1'b1;
                    1: draw_character = (char_x == 4);
                    2: draw_character = (char_x == 3);
                    3,4: draw_character = (char_x == 2);
                    5,6: draw_character = (char_x == 1);
                endcase
            end

            // 8
            8: begin
                case (char_y)
                    0,3,6: draw_character = (char_x >= 1 && char_x <= 3);
                    1,2,4,5: draw_character =
                        (char_x == 0 || char_x == 4);
                endcase
            end

            // 9
            9: begin
                case (char_y)
                    0: draw_character = (char_x >= 1 && char_x <= 3);
                    1,2: draw_character = (char_x == 0 || char_x == 4);
                    3: draw_character = (char_x >= 1 && char_x <= 4);
                    4,5: draw_character = (char_x == 4);
                    6: draw_character = (char_x >= 1 && char_x <= 3);
                endcase
            end

            // 10 (display the 0 pattern; draw the 1 separately)
            10: begin
                case (char_y)
                    0,6: draw_character = (char_x >= 1 && char_x <= 3);
                    1,2,3,4,5: draw_character =
                        (char_x == 0 || char_x == 4);
                endcase
            end

            // JACK (J)
            11: begin
                case (char_y)
                    0: draw_character = (char_x >= 1 && char_x <= 4);
                    1,2,3,4,5: draw_character = (char_x == 3);
                    6: draw_character = (char_x == 1 || char_x == 2 || char_x == 3);
                endcase
            end

            // QUEEN (Q)
            12: begin
                case (char_y)
                    0,6: draw_character = (char_x >= 1 && char_x <= 3);
                    1,2,3,4: draw_character =
                        (char_x == 0 || char_x == 4);
                    5: draw_character = (char_x == 0 || char_x == 3 || char_x == 4);
                endcase
            end

            // KING (K)
            13: begin
                case (char_y)
                    0,6: draw_character = (char_x == 0 || char_x == 4);
                    1,5: draw_character = (char_x == 0 || char_x == 3);
                    2,4: draw_character = (char_x == 0 || char_x == 2);
                    3: draw_character = (char_x == 0 || char_x == 1);
                endcase
            end

			// LETTER B
			15: begin
				 case(char_y)
					  0,1,2,3,4,5,6:
							draw_character = (char_x == 0 ||
								 (char_x == 4 && char_y != 0 &&
								  char_y != 3 && char_y != 6) ||
								 (char_x > 0 && char_x < 4 &&
								  (char_y == 0 || char_y == 3 || char_y == 6)));
				 endcase
			end

			// LETTER C
			16: begin
				 case(char_y)
					  0,6: draw_character = (char_x >= 1 && char_x <= 3);
					  1,2,3,4,5: draw_character = (char_x == 0);
				 endcase
			end

			// LETTER D
			17: begin
				 case(char_y)
					  0,6: draw_character = (char_x <= 3);
					  1,2,3,4,5: draw_character = (char_x == 0 || char_x == 4);
				 endcase
			end

			// LETTER E
			18: begin
				 case(char_y)
					  0,3,6: draw_character = (char_x <= 4);
					  1,2,4,5: draw_character = (char_x == 0);
				 endcase
			end

			// LETTER F
			19: begin
				 case(char_y)
					  0,3: draw_character = (char_x <= 4);
					  1,2,4,5,6: draw_character = (char_x == 0);
				 endcase
			end

			// LETTER G
			20: begin
				 case(char_y)
					  0,6: draw_character = (char_x >= 1 && char_x <= 3);
					  1,2: draw_character = (char_x == 0);
					  3: draw_character = (char_x == 0 || char_x >= 2);
					  4,5: draw_character = (char_x == 0 || char_x == 4);
				 endcase
			end

			// LETTER H
			21: begin
				 case(char_y)
					  0,1,2,4,5,6: draw_character = (char_x == 0 || char_x == 4);
					  3: draw_character = 1'b1;
				 endcase
			end

			// LETTER I
			22: begin
				 case(char_y)
					  0,6: draw_character = (char_x <= 4);
					  1,2,3,4,5: draw_character = (char_x == 2);
				 endcase
			end

			// LETTER L
			23: begin
				 case(char_y)
					  0,1,2,3,4,5: draw_character = (char_x == 0);
					  6: draw_character = (char_x <= 4);
				 endcase
			end

			// LETTER M
			24: begin
				 case(char_y)
					  0,1: draw_character = (char_x == 0 || char_x == 4);
					  2: draw_character = (char_x == 0 || char_x == 1 || char_x == 3 || char_x == 4);
					  3,4,5,6: draw_character = (char_x == 0 || char_x == 2 || char_x == 4);
				 endcase
			end

			// LETTER N
			25: begin
				 case(char_y)
					  0,1,2,3,4,5,6:
							draw_character = (char_x == 0 || char_x == 4 ||
													char_x == char_y);
				 endcase
			end

			// LETTER O
			26: begin
				 case(char_y)
					  0,6: draw_character = (char_x >= 1 && char_x <= 3);
					  1,2,3,4,5: draw_character = (char_x == 0 || char_x == 4);
				 endcase
			end

			// LETTER P
			27: begin
				 case(char_y)
					  0,3: draw_character = (char_x <= 3);
					  1,2: draw_character = (char_x == 0 || char_x == 4);
					  4,5,6: draw_character = (char_x == 0);
				 endcase
			end

			// LETTER R
			28: begin
				 case(char_y)
					  0,3: draw_character = (char_x <= 3);
					  1,2: draw_character = (char_x == 0 || char_x == 4);
					  4: draw_character = (char_x == 0 || char_x == 4);
					  5: draw_character = (char_x == 0 || char_x == 4);
					  6: draw_character = (char_x == 0 || char_x == 4);
				 endcase
			end

			// LETTER S
			29: begin
				 case(char_y)
					  0,3,6: draw_character = (char_x >= 1 && char_x <= 3);
					  1,2: draw_character = (char_x == 0);
					  4,5: draw_character = (char_x == 4);
				 endcase
			end

			// LETTER T
			30: begin
				 case(char_y)
					  0: draw_character = (char_x <= 4);
					  1,2,3,4,5,6: draw_character = (char_x == 2);
				 endcase
			end

			// LETTER U
			31: begin
				 case(char_y)
					  0,1,2,3,4,5: draw_character = (char_x == 0 || char_x == 4);
					  6: draw_character = (char_x >= 1 && char_x <= 3);
				 endcase
			end

			// LETTER V
			32: begin
				 case(char_y)
					  0,1,2,3: draw_character = (char_x == 0 || char_x == 4);
					  4,5: draw_character = (char_x == 1 || char_x == 3);
					  6: draw_character = (char_x == 2);
				 endcase
			end

			// LETTER W
			33: begin
				 case(char_y)
					  0,1,2,3: draw_character = (char_x == 0 || char_x == 4);
					  4,5: draw_character = (char_x == 0 || char_x == 2 || char_x == 4);
					  6: draw_character = (char_x == 0 ||char_x == 1 ||char_x == 3 || char_x == 4);
				 endcase
			end

			// LETTER X
			34: begin
				 case(char_y)
					  0,6: draw_character = (char_x == 0 || char_x == 4);
					  1,5: draw_character = (char_x == 1 || char_x == 3);
					  2,3,4: draw_character = (char_x == 2);
				 endcase
			end

			// LETTER Y
			35: begin
				 case(char_y)
					  0,1: draw_character = (char_x == 0 || char_x == 4);
					  2,3: draw_character = (char_x == 1 || char_x == 3);
					  4,5,6: draw_character = (char_x == 2);
				 endcase
			end

			// LETTER Z
			36: begin
				 case(char_y)
					  0,6: draw_character = (char_x <= 4);
					  1: draw_character = (char_x == 4);
					  2: draw_character = (char_x == 3);
					  3: draw_character = (char_x == 2);
					  4: draw_character = (char_x == 1);
					  5: draw_character = (char_x == 0);
				 endcase
			end
			// EXCLAMATION MARK (!)
			37: begin
				 case(char_y)
					  0,1,2,3,4: draw_character = (char_x == 2);
					  6: draw_character = (char_x == 2);
				 endcase
			end

			// COMMA (,)
			38: begin
				 case(char_y)
					  5: draw_character = (char_x == 2);
					  6: draw_character = (char_x == 1);
				 endcase
			end

			// COLON (:)
			39: begin
				 case(char_y)
					  1,2,4,5: draw_character = (char_x == 2);
				 endcase
			end

			// DOLLAR SIGN ($)
			40: begin
				 case(char_y)
					  0,6: draw_character = (char_x == 2);
					  1: draw_character = (char_x >= 1 && char_x <= 4);
					  2: draw_character = (char_x == 0 || char_x == 2);
					  3: draw_character = (char_x >= 1 && char_x <= 3);
					  4: draw_character = (char_x == 2 || char_x == 4);
					  5: draw_character = (char_x <= 3);
				 endcase
			end

            default: draw_character = 1'b0;

        endcase
    end
	 
	 
endfunction


// Select letters for BLACKJACK
function [4:0] title_letter;
    input [3:0] index;
    begin
        case(index)
            0: title_letter = 15; // B
            1: title_letter = 23; // L
            2: title_letter = 1;  // A
            3: title_letter = 16; // C
            4: title_letter = 13; // K
            5: title_letter = 11; // J
            6: title_letter = 1;  // A
            7: title_letter = 16; // C
            8: title_letter = 13; // K
            default: title_letter = 0;
        endcase
    end
endfunction


// Select letters for DEAL TO START
function [4:0] subtitle_letter;
    input [3:0] index;
    begin
        case(index)
            0: subtitle_letter = 17;  // D
            1: subtitle_letter = 18;  // E
            2: subtitle_letter = 1;   // A
            3: subtitle_letter = 23;  // L
            4: subtitle_letter = 0;   // SPACE
            5: subtitle_letter = 30;  // T
            6: subtitle_letter = 26;  // O
            7: subtitle_letter = 0;   // SPACE
            8: subtitle_letter = 29;  // S
            9: subtitle_letter = 30;  // T
            10: subtitle_letter = 1;  // A
            11: subtitle_letter = 28; // R
            12: subtitle_letter = 30; // T
            default: subtitle_letter = 0;
        endcase
    end
endfunction

// Welcome screen appears before cards are dealt
wire intro_screen = (game_state == 6'd0);


// BLACKJACK title: scale 6
wire [9:0] title_local_x = (x - 10'd158) / 6;
wire [9:0] title_local_y = (y - 10'd150) / 6;

wire [3:0] title_index = title_local_x / 6;
wire [2:0] title_char_x = title_local_x % 6;
wire [2:0] title_char_y = title_local_y;

wire [4:0] title_char = title_letter(title_index);

wire title_pixel =
    (x >= 158 && x < 482 &&
     y >= 150 && y < 192 &&
     title_char_x < 5 &&
     draw_character(title_char, title_char_x, title_char_y));


// DEAL TO START subtitle: scale 4
wire [9:0] subtitle_local_x = (x - 10'd166) / 4;
wire [9:0] subtitle_local_y = (y - 10'd225) / 4;

wire [3:0] subtitle_index = subtitle_local_x / 6;
wire [2:0] subtitle_char_x = subtitle_local_x % 6;
wire [2:0] subtitle_char_y = subtitle_local_y;

wire [4:0] subtitle_char = subtitle_letter(subtitle_index);

wire subtitle_pixel =
    (x >= 166 && x < 478 &&
     y >= 225 && y < 253 &&
     subtitle_char_x < 5 &&
     draw_character(subtitle_char, subtitle_char_x, subtitle_char_y));
	  
	  
// ---------------- CENTER MESSAGES ----------------
// id: 0 none, 1 BLACKJACK, 2 PLAYER WIN!, 3 DEALER WIN!, 4 PUSH,
//     5 PLAYER BUST!, 6 HIT, STAND, OR DOUBLE,
//     7 PLACE A BET FIRST, 8 BET EXCEEDS YOUR BALANCE

function [4:0] msg_len;
    input [3:0] id;
    begin
        case (id)
            4'd1: msg_len = 5'd10;   // BLACKJACK!
            4'd2: msg_len = 5'd11;   // PLAYER WIN!
            4'd3: msg_len = 5'd11;   // DEALER WIN!
            4'd4: msg_len = 5'd4;   // PUSH
            4'd5: msg_len = 5'd12;   // PLAYER BUST!
            4'd6: msg_len = 5'd21;   // HIT, STAND, OR DOUBLE
            4'd7: msg_len = 5'd17;   // PLACE A BET FIRST
            4'd8: msg_len = 5'd24;   // BET EXCEEDS YOUR BALANCE
            default: msg_len = 5'd0;
        endcase
    end
endfunction

function [5:0] msg_letter;
    input [3:0] id;
    input [4:0] index;
    begin
        msg_letter = 6'd0;
        case (id)

            // BLACKJACK
            4'd1: case (index)
                0: msg_letter = 15;  // B
                1: msg_letter = 23;  // L
                2: msg_letter = 1;  // A
                3: msg_letter = 16;  // C
                4: msg_letter = 13;  // K
                5: msg_letter = 11;  // J
                6: msg_letter = 1;  // A
                7: msg_letter = 16;  // C
                8: msg_letter = 13;  // K
					 9: msg_letter = 37;  //!
                default: msg_letter = 0;
            endcase

            // PLAYER WIN!
            4'd2: case (index)
                0: msg_letter = 27;  // P
                1: msg_letter = 23;  // L
                2: msg_letter = 1;  // A
                3: msg_letter = 35;  // Y
                4: msg_letter = 18;  // E
                5: msg_letter = 28;  // R
                6: msg_letter = 0;  // SPACE
                7: msg_letter = 33;  // W
                8: msg_letter = 22;  // I
                9: msg_letter = 25;  // N
                10: msg_letter = 37;  // !
                default: msg_letter = 0;
            endcase

            // DEALER WIN!
            4'd3: case (index)
                0: msg_letter = 17;  // D
                1: msg_letter = 18;  // E
                2: msg_letter = 1;  // A
                3: msg_letter = 23;  // L
                4: msg_letter = 18;  // E
                5: msg_letter = 28;  // R
                6: msg_letter = 0;  // SPACE
                7: msg_letter = 33;  // W
                8: msg_letter = 22;  // I
                9: msg_letter = 25;  // N
                10: msg_letter = 37;  // !
                default: msg_letter = 0;
            endcase

            // PUSH
            4'd4: case (index)
                0: msg_letter = 27;  // P
                1: msg_letter = 31;  // U
                2: msg_letter = 29;  // S
                3: msg_letter = 21;  // H
                default: msg_letter = 0;
            endcase

            // PLAYER BUST!
            4'd5: case (index)
                0: msg_letter = 27;  // P
                1: msg_letter = 23;  // L
                2: msg_letter = 1;  // A
                3: msg_letter = 35;  // Y
                4: msg_letter = 18;  // E
                5: msg_letter = 28;  // R
                6: msg_letter = 0;  // SPACE
                7: msg_letter = 15;  // B
                8: msg_letter = 31;  // U
                9: msg_letter = 29;  // S
                10: msg_letter = 30;  // T
                11: msg_letter = 37;  // !
                default: msg_letter = 0;
            endcase

            // HIT, STAND, OR DOUBLE
            4'd6: case (index)
                0: msg_letter = 21;  // H
                1: msg_letter = 22;  // I
                2: msg_letter = 30;  // T
                3: msg_letter = 38;  // ,
                4: msg_letter = 0;  // SPACE
                5: msg_letter = 29;  // S
                6: msg_letter = 30;  // T
                7: msg_letter = 1;  // A
                8: msg_letter = 25;  // N
                9: msg_letter = 17;  // D
                10: msg_letter = 38;  // ,
                11: msg_letter = 0;  // SPACE
                12: msg_letter = 26;  // O
                13: msg_letter = 28;  // R
                14: msg_letter = 0;  // SPACE
                15: msg_letter = 17;  // D
                16: msg_letter = 26;  // O
                17: msg_letter = 31;  // U
                18: msg_letter = 15;  // B
                19: msg_letter = 23;  // L
                20: msg_letter = 18;  // E
                default: msg_letter = 0;
            endcase

            // PLACE A BET FIRST
            4'd7: case (index)
                0: msg_letter = 27;  // P
                1: msg_letter = 23;  // L
                2: msg_letter = 1;  // A
                3: msg_letter = 16;  // C
                4: msg_letter = 18;  // E
                5: msg_letter = 0;  // SPACE
                6: msg_letter = 1;  // A
                7: msg_letter = 0;  // SPACE
                8: msg_letter = 15;  // B
                9: msg_letter = 18;  // E
                10: msg_letter = 30;  // T
                11: msg_letter = 0;  // SPACE
                12: msg_letter = 19;  // F
                13: msg_letter = 22;  // I
                14: msg_letter = 28;  // R
                15: msg_letter = 29;  // S
                16: msg_letter = 30;  // T
                default: msg_letter = 0;
            endcase

            // BET EXCEEDS YOUR BALANCE
            4'd8: case (index)
                0: msg_letter = 15;  // B
                1: msg_letter = 18;  // E
                2: msg_letter = 30;  // T
                3: msg_letter = 0;  // SPACE
                4: msg_letter = 18;  // E
                5: msg_letter = 34;  // X
                6: msg_letter = 16;  // C
                7: msg_letter = 18;  // E
                8: msg_letter = 18;  // E
                9: msg_letter = 17;  // D
                10: msg_letter = 29;  // S
                11: msg_letter = 0;  // SPACE
                12: msg_letter = 35;  // Y
                13: msg_letter = 26;  // O
                14: msg_letter = 31;  // U
                15: msg_letter = 28;  // R
                16: msg_letter = 0;  // SPACE
                17: msg_letter = 15;  // B
                18: msg_letter = 1;  // A
                19: msg_letter = 23;  // L
                20: msg_letter = 1;  // A
                21: msg_letter = 25;  // N
                22: msg_letter = 16;  // C
                23: msg_letter = 18;  // E
                default: msg_letter = 0;
            endcase

            default: msg_letter = 0;
        endcase
    end
endfunction

// which message goes on each line
wire waiting = (game_state == 6'd0) || (game_state == 6'd13);   // START or PLAY_AGAIN

// line A (y = 225): round result, or the hint while the player is deciding
wire [3:0] msg_a = (result != 3'd0)     ? {1'b0, result} :
                   (game_state == 6'd3) ? 4'd6 : 4'd0;

// line B (y = 270): bet warnings while waiting for a deal
wire [3:0] msg_b = (!waiting)    ? 4'd0 :
                   (no_bet)      ? 4'd7 :
                   (not_allowed) ? 4'd8 : 4'd0;

// ---- line A, scale 4, centered ----
wire [4:0] len_a = msg_len(msg_a);
wire [9:0] a_x0  = 10'd320 - ({5'd0, len_a} * 10'd12);
wire [9:0] a_w   = {5'd0, len_a} * 10'd24;

wire [9:0] a_local_x = (x - a_x0) / 4;
wire [9:0] a_local_y = (y - 10'd225) / 4;

wire [4:0] a_index  = a_local_x / 6;
wire [2:0] a_char_x = a_local_x % 6;
wire [2:0] a_char_y = a_local_y;

wire [5:0] a_char = msg_letter(msg_a, a_index);

wire line_a_pixel =
    (len_a != 5'd0) &&
    (x >= a_x0 && x < a_x0 + a_w &&
     y >= 225 && y < 253 &&
     a_char_x < 5 &&
     draw_character(a_char, a_char_x, a_char_y));

// ---- line B, scale 4, centered ----
wire [4:0] len_b = msg_len(msg_b);
wire [9:0] b_x0  = 10'd320 - ({5'd0, len_b} * 10'd12);
wire [9:0] b_w   = {5'd0, len_b} * 10'd24;

wire [9:0] b_local_x = (x - b_x0) / 4;
wire [9:0] b_local_y = (y - 10'd270) / 4;

wire [4:0] b_index  = b_local_x / 6;
wire [2:0] b_char_x = b_local_x % 6;
wire [2:0] b_char_y = b_local_y;

wire [5:0] b_char = msg_letter(msg_b, b_index);

wire line_b_pixel =
    (len_b != 5'd0) &&
    (x >= b_x0 && x < b_x0 + b_w &&
     y >= 270 && y < 298 &&
     b_char_x < 5 &&
     draw_character(b_char, b_char_x, b_char_y));


// ---------------- BET / BANK LABELS ----------------
// "BANK: $#####" and "BET: $####", no leading zeros, scale 2

function [2:0] num_digits;
    input [16:0] v;
    begin
        if (v >= 17'd10000)     num_digits = 3'd5;
        else if (v >= 17'd1000) num_digits = 3'd4;
        else if (v >= 17'd100)  num_digits = 3'd3;
        else if (v >= 17'd10)   num_digits = 3'd2;
        else                    num_digits = 3'd1;
    end
endfunction

function [5:0] money_char;
    input        is_bank;
    input [4:0]  idx;
    input [16:0] value;
    input [2:0]  nd;
    reg [4:0] plen;
    reg [4:0] k;
    reg [2:0] p;
    reg [3:0] d;
    begin
        money_char = 6'd0;
        plen = is_bank ? 5'd7 : 5'd6;

        if (idx < plen) begin
            if (is_bank) begin
                case (idx)
                    0: money_char = 15;  // B
                    1: money_char = 1;   // A
                    2: money_char = 25;  // N
                    3: money_char = 13;  // K
                    4: money_char = 39;  // :
                    5: money_char = 0;   // SPACE
                    6: money_char = 40;  // $
                    default: money_char = 0;
                endcase
            end
            else begin
                case (idx)
                    0: money_char = 15;  // B
                    1: money_char = 18;  // E
                    2: money_char = 30;  // T
                    3: money_char = 39;  // :
                    4: money_char = 0;   // SPACE
                    5: money_char = 40;  // $
                    default: money_char = 0;
                endcase
            end
        end
        else begin
            k = idx - plen;                  // which digit, 0 = leftmost
            if (k < nd) begin
                p = nd - 3'd1 - k;           // place value of that digit
                case (p)
                    3'd0: d = value % 10;
                    3'd1: d = (value / 10) % 10;
                    3'd2: d = (value / 100) % 10;
                    3'd3: d = (value / 1000) % 10;
                    default: d = (value / 10000) % 10;
                endcase
                money_char = display_digit(d);
            end
        end
    end
endfunction

// ---- BET: top right, starts at x = 500, y = 15 ----
wire [16:0] bet_val = {7'd0, bet};
wire [2:0]  bet_nd  = num_digits(bet_val);
wire [4:0]  bet_len = 5'd6 + {2'd0, bet_nd};
wire [9:0]  bet_w   = {5'd0, bet_len} * 10'd12;

wire [9:0] bet_local_x = (x - 10'd500) / 2;
wire [9:0] bet_local_y = (y - 10'd15) / 2;

wire [4:0] bet_index  = bet_local_x / 6;
wire [2:0] bet_char_x = bet_local_x % 6;
wire [2:0] bet_char_y = bet_local_y;

wire bet_pixel =
    (x >= 500 && x < 500 + bet_w &&
     y >= 15 && y < 29 &&
     bet_char_x < 5 &&
     draw_character(money_char(1'b0, bet_index, bet_val, bet_nd),
                    bet_char_x, bet_char_y));

// ---- BANK: bottom right, starts at x = 480, y = 440 ----
wire [16:0] bank_val = {5'd0, bank};
wire [2:0]  bank_nd  = num_digits(bank_val);
wire [4:0]  bank_len = 5'd7 + {2'd0, bank_nd};
wire [9:0]  bank_w   = {5'd0, bank_len} * 10'd12;

wire [9:0] bank_local_x = (x - 10'd480) / 2;
wire [9:0] bank_local_y = (y - 10'd440) / 2;

wire [4:0] bank_index  = bank_local_x / 6;
wire [2:0] bank_char_x = bank_local_x % 6;
wire [2:0] bank_char_y = bank_local_y;

wire bank_pixel =
    (x >= 480 && x < 480 + bank_w &&
     y >= 440 && y < 454 &&
     bank_char_x < 5 &&
     draw_character(money_char(1'b1, bank_index, bank_val, bank_nd),
                    bank_char_x, bank_char_y));



    always @(*) begin
	 
	 // Felt background
        VGA_R = 8'd53;
        VGA_G = 8'd101;
        VGA_B = 8'd77;
	 
	 if (intro_screen) begin
        	  
			  // Draw BLACKJACK
		 if (title_pixel) begin
			  VGA_R = 8'd255;
			  VGA_G = 8'd255;
			  VGA_B = 8'd255;
		 end

		 // Draw DEAL TO START
		 else if (subtitle_pixel) begin
			  VGA_R = 8'd255;
			  VGA_G = 8'd255;
			  VGA_B = 8'd255;
		 end
end
		  
// Round result / hint (line A)
		if (line_a_pixel) begin
			VGA_R = 8'd255;
			VGA_G = 8'd255;
			VGA_B = 8'd255;
		end

		// Bet warnings (line B), yellow
		if (line_b_pixel) begin
			VGA_R = 8'd255;
			VGA_G = 8'd220;
			VGA_B = 8'd60;
		end
		
		  // Bet amount in the top-right corner
		if (bet_pixel) begin
			VGA_R = 8'd255;
		 VGA_G = 8'd255;
		 VGA_B = 8'd255;
	end

	// Bank amount in the bottom-right corner
	if (bank_pixel) begin
		 VGA_R = 8'd255;
		 VGA_G = 8'd255;
		 VGA_B = 8'd255;
	end

        // White card face
        if (card_pixel) begin
            VGA_R = 8'd255;
            VGA_G = 8'd255;
            VGA_B = 8'd255;
        end

        // Face down card: blue back with a white border
        if (face_down && local_x >= 5 && local_x < 70 && local_y >= 5 && local_y < 105) begin
            VGA_R = 8'd30;
            VGA_G = 8'd50;
            VGA_B = 8'd140;
        end

        // Rank and suit are red for hearts/diamonds, black for spades/clubs
        // (face down cards show no rank or suit)
        if (card_pixel && (face_down == 1'b0) && (rank_pixel || suit_pixel)) begin
            if (card_suit == 2'b00 || card_suit == 2'b01) begin
                VGA_R = 8'd220;
                VGA_G = 8'd20;
                VGA_B = 8'd40;
            end else begin
                VGA_R = 8'd15;
                VGA_G = 8'd15;
                VGA_B = 8'd15;
            end
        end

        // Blank outside the active video area
        if (!video_on) begin
            VGA_R = 8'd0;
            VGA_G = 8'd0;
            VGA_B = 8'd0;
        end
    end

endmodule