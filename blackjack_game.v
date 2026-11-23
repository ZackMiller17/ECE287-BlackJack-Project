//////////////////////////////////////////////////////////////
//                        BLACKJACK                         //
//                                                          //
// KEY[0] RST                                               //
// KEY[1] DOUBLE DOWN                                       //
// KEY[2] DEAL / STAND                                      //
// KEY[3] HIT                                               //
//                                                          //
//                                                          //
//                                                          //
//////////////////////////////////////////////////////////////


module blackjack_game(

	//////////// CLOCK //////////
	input 		          		CLOCK_50,

	//////////// SEG7 //////////
	output		     [6:0]		HEX0,
	output		     [6:0]		HEX1,
	output		     [6:0]		HEX2,
	output		     [6:0]		HEX3,
	output		     [6:0]		HEX4,
	output		     [6:0]		HEX5,

	//////////// KEY //////////
	input 		     [3:0]		KEY,

	//////////// LED //////////
	output		     [9:0]		LEDR,

	//////////// SW //////////
	input 		     [9:0]		SW,

	//////////// VGA //////////
	output		          		VGA_BLANK_N,
	output		     [7:0]		VGA_B,
	output		          		VGA_CLK,
	output		     [7:0]		VGA_G,
	output		          		VGA_HS,
	output		     [7:0]		VGA_R,
	output		          		VGA_SYNC_N,
	output		          		VGA_VS
);

// basic signals
wire clk;
wire rst;
assign clk = CLOCK_50;
assign rst = KEY[0]; //resets everything



// ------ turns a button press into a single-clock pulse ------------
reg [2:0] key_prev;
always @(posedge clk)
	key_prev <= KEY[3:1];

wire double_btn = key_prev[0] & ~KEY[1];   // KEY[1]: double down (during a hand)
wire deal_btn   = key_prev[1] & ~KEY[2];   // KEY[2]: deal a new round
wire stand_btn  = key_prev[1] & ~KEY[2];   // KEY[2]: stand (during a hand)
wire hit_btn    = key_prev[2] & ~KEY[3];   // KEY[3]: hit


// ------------ VGA signals  ---------------

reg pixel_clk;

wire [9:0] pixel_x;
wire [9:0] pixel_y;
wire hsync;
wire vsync;
wire video_on;

wire [7:0] red;
wire [7:0] green;
wire [7:0] blue;

// 25 MHz pixel clock made from the 50 MHz clock
always @(posedge CLOCK_50 or negedge KEY[0]) begin
	if (!KEY[0])
		pixel_clk <= 1'b0;
	else
		pixel_clk <= ~pixel_clk;
end

// ------------ VGA modules ---------------------------


// VGA WIRES

wire [35:0] p_hand;
wire [35:0] d_hand;
wire [3:0]  p_num;
wire [3:0]  d_num;
wire       reveal;

wire [11:0] bank;
wire [9:0] cur_bet;
wire not_allowed;
wire no_bet;
wire [5:0] game_state;

wire [2:0] result;


blackjack_controller vga (
	.pixel_clk(pixel_clk),
	.reset(~KEY[0]),
	.x(pixel_x),
	.y(pixel_y),
	.hsync(hsync),
	.vsync(vsync),
	.video_on(video_on)
);

blackjack_render renderer (
	.x(pixel_x),
	.y(pixel_y),
	.video_on(video_on),
	.p_hand(p_hand),
	.d_hand(d_hand),
	.p_num(p_num),
	.d_num(d_num),
	.reveal(reveal),
	.result(result),
	.not_allowed(not_allowed),
	.no_bet(no_bet),
	.bank(bank),
	.bet(cur_bet),
	.game_state(game_state),
	.VGA_R(red),
	.VGA_G(green),
	.VGA_B(blue)

);

assign VGA_R = red;
assign VGA_G = green;
assign VGA_B = blue;

assign VGA_HS = hsync;
assign VGA_VS = vsync;
assign VGA_CLK = pixel_clk;
assign VGA_BLANK_N = video_on;
assign VGA_SYNC_N = 1'b0;


// ------------ game_core stuff ---------------------------

wire       deck_ready;
wire       deck_shuffled;
wire [5:0] player_val;
wire [5:0] dealer_val;


game_core the_game(
	.clk(clk),
	.rst(rst),
	.deck_ready(deck_ready),
	.deck_shuffled(deck_shuffled),
	.deal(deal_btn),
	.hit(hit_btn),
	.stand(stand_btn),
	.double(double_btn),
	.player_val(player_val),
	.dealer_val(dealer_val),
	.game_state(game_state),
	.reveal(reveal),
	.result(result),
	
	.p_hand(p_hand),
	.d_hand(d_hand),
	.p_num(p_num),
	.d_num(d_num),
	
	.bet(SW[9:0]),
	.bank(bank),
	.cur_bet(cur_bet),
	.not_allowed(not_allowed),
	.no_bet(no_bet)
);


// ---------- seven segment displays ----------

// HEX1:HEX0 = player's total
wire [6:0] pv_ones;
wire [6:0] pv_tens;

three_decimal_vals_w_neg player_display(
	.val({2'b00, player_val}),
	.seg7_dig0(pv_ones),
	.seg7_dig1(pv_tens)
);


assign HEX0 = pv_ones;
assign HEX1 = pv_tens;
assign HEX2 = 1'b0;
assign HEX3 = 1'b0;                 
assign HEX4 = 1'b0;
assign HEX5 = 1'b0;

// status LEDs
assign LEDR[0]   = deck_ready;
assign LEDR[1]   = deck_shuffled;
assign LEDR[3:2] = 2'b00;
assign LEDR[9:4] = game_state;

endmodule