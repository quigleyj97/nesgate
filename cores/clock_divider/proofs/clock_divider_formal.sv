// Properties of the clock divider, checked on every rising edge of its input
// clock: the output starts low, then toggles on every DIVIDE_BY-th edge, so
// each half of its period lasts exactly DIVIDE_BY input edges.
//
// GHDL elaborates generics away, so the netlist is synthesized for one divisor
// at a time (see util/formal_check), and each task of clock_divider.sby sets
// DIVIDE_BY to match the netlist it reads.
module clock_divider_formal #(
    parameter DIVIDE_BY = 2
) (
    input clk
);
    wire clk_out;

    clock_divider dut (
        .clk(clk),
        .clk_out(clk_out)
    );

    // Wide enough to count up to DIVIDE_BY, one past the longest legal level
    localparam WIDTH = $clog2(DIVIDE_BY + 1);

    reg f_past_valid = 1'b0;
    reg f_out_was = 1'b0;
    // How many input edges the output had held its level through, on the
    // step before
    reg [WIDTH-1:0] f_held_was = 0;
    // Rising edges of the output so far, saturating at 3 (for the covers)
    reg [1:0] f_rises = 2'd0;

    wire f_toggled = f_past_valid && clk_out != f_out_was;
    // How many input edges the output has held its current level through
    wire [WIDTH-1:0] f_held = (!f_past_valid || f_toggled) ? 0 : f_held_was + 1'b1;

    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        f_out_was <= clk_out;
        f_held_was <= f_held;
        if (f_toggled && clk_out && f_rises != 2'd3) f_rises <= f_rises + 1'b1;
    end

    always @* begin
        if (!f_past_valid) begin
            check_power_up: assert (!clk_out);
        end

        // Together, these pin the output to floor(edges / DIVIDE_BY) mod 2
        check_not_early: assert (!f_toggled || f_held_was == DIVIDE_BY - 1);
        check_not_late: assert (f_held < DIVIDE_BY);

        reach_rise: cover (f_toggled && clk_out);
        reach_fall: cover (f_toggled && !clk_out);
        // A whole period: rise, fall, and rise again
        reach_full_period: cover (f_toggled && clk_out && f_rises == 2'd1);
    end
endmodule
