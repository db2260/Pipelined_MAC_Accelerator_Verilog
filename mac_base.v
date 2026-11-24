// Baseline: multiply + add + round + saturate in ONE cycle (long critical path).
// Used only to compare Fmax / latency against mac_pipe.
module mac_base #(
    parameter DW = 16, parameter FRAC = 15, parameter GUARD = 8
)(
    input  wire                         clk, rst,
    input  wire                         in_valid, in_first, in_last,
    input  wire signed [DW-1:0]         in_a, in_b,
    output reg                          out_valid,
    output reg  signed [DW-1:0]         out_data
);
    localparam AW = 2*DW + GUARD;
    reg  signed [AW-1:0] acc;
    wire signed [AW-1:0] nxt  = (in_first ? {AW{1'b0}} : acc) + in_a * in_b;
    wire signed [AW-1:0] half = {{(AW-FRAC){1'b0}}, 1'b1, {(FRAC-1){1'b0}}};
    wire signed [AW-1:0] rnd  = (nxt + half) >>> FRAC;
    wire signed [AW-1:0] smax = {{(AW-DW+1){1'b0}}, {(DW-1){1'b1}}};
    wire signed [AW-1:0] smin = {{(AW-DW+1){1'b1}}, {(DW-1){1'b0}}};

    always @(posedge clk) begin
        out_valid <= rst ? 1'b0 : (in_valid & in_last);
        if (in_valid) begin
            acc <= nxt;
            if (in_last)
                out_data <= (rnd > smax) ? smax[DW-1:0] :
                            (rnd < smin) ? smin[DW-1:0] : rnd[DW-1:0];
        end
    end
endmodule
