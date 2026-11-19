// Real Phi1/Phi2 clocks for the decoder's unit proofs, made from the
// metaclock: the phases alternate and never overlap, as the
// phased_clock_generator proof shows they do, and each phase lasts anywhere
// from 3 metaclock cycles (the fewest clocks.md allows) to 7 (the top level's
// METACLOCKS_PER_PHASE). end_phase, a free input, picks each phase's length.
// The CPU starts in Phi1.
//
// Every step is one metaclock edge. On a phase's last step (last_edge), the
// phase's latches have had at least two edges to settle, which is as deep as
// the decoder's latch chains go, so that's where the harnesses read the
// outputs. first_edge is the first step of a phase, the only one on which the
// harnesses let their inputs change.
module two_phase_clock (
    input metaclock,
    input end_phase,
    output reg phi1,
    output reg phi2,
    output first_edge,
    output last_edge
);
    localparam MIN_PHASE_EDGES = 3'd3;
    localparam MAX_PHASE_EDGES = 3'd7;

    initial phi1 = 1'b1;
    initial phi2 = 1'b0;
    // The metaclock edges so far in this phase, counting this one
    reg [2:0] edges = 3'd1;

    assign first_edge = edges == 3'd1;
    assign last_edge = edges == MAX_PHASE_EDGES
        || (edges >= MIN_PHASE_EDGES && end_phase);

    always @(posedge metaclock) begin
        if (last_edge) begin
            phi1 <= !phi1;
            phi2 <= !phi2;
            edges <= 3'd1;
        end else begin
            edges <= edges + 3'd1;
        end
    end
endmodule
