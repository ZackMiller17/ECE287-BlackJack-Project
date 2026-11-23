module blackjack_controller (
    input pixel_clk,
    input reset,

    output reg [9:0] x,
    output reg [9:0] y,

    output hsync,
    output vsync,
    output video_on
);

    // Horizontal counter
    always @(posedge pixel_clk or posedge reset) begin
        if (reset) begin
            x <= 0;
            y <= 0;
        end
        else begin
            if (x == 799) begin
                x <= 0;

                if (y == 524)
                    y <= 0;
                else
                    y <= y + 1;
            end
            else begin
                x <= x + 1;
            end
        end
    end

    // Horizontal synchronization
    assign hsync = ~((x >= 656) && (x < 752));

    // Vertical synchronization
    assign vsync = ~((y >= 490) && (y < 492));

    // Visible screen area
    assign video_on = (x < 640) && (y < 480);

endmodule