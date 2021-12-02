`timescale 1ns / 1ps


module bit_syncer_fdre #(
    parameter DATA_WIDTH = 32,
    parameter INIT_VALUE = 1
) (
    input                   CLK_SRC ,
    input                   CLK_DST ,
    input  [DATA_WIDTH-1:0] DATA_IN ,
    output [DATA_WIDTH-1:0] DATA_OUT
);

    (* ASYNC_REG="true" *) logic [DATA_WIDTH-1 : 0] meta_0_out;
    (* ASYNC_REG="true" *) logic [DATA_WIDTH-1 : 0] meta_1_out;
    (* ASYNC_REG="true" *) logic [DATA_WIDTH-1 : 0] meta_2_out;
    (* ASYNC_REG="true" *) logic [DATA_WIDTH-1 : 0] meta_3_out;
    (* ASYNC_REG="true" *) logic [DATA_WIDTH-1 : 0] data_vector_src;


    genvar index;
    generate
        for (index=0; index < DATA_WIDTH; index++)
        begin

            FDRE #(
                .INIT         (1'b0), // Initial value of register, 1'b0, 1'b1
                .IS_C_INVERTED(1'b0), // Optional inversion for C
                .IS_D_INVERTED(1'b0), // Optional inversion for D
                .IS_R_INVERTED(1'b0)  // Optional inversion for R
            ) fdre_src_inst (
                .C (CLK_SRC        ), // 1-bit input: Clock
                .Q (data_vector_src[index]), // 1-bit output: Data
                .CE(1'b1           ), // 1-bit input: Clock enable
                .D (DATA_IN[index]        ), // 1-bit input: Data
                .R (1'b0           )  // 1-bit input: Synchronous reset
            );

            FDRE #(
                .INIT         (INIT_VALUE), // Initial value of register, 1'b0, 1'b1
                .IS_C_INVERTED(1'b0      ), // Optional inversion for C
                .IS_D_INVERTED(1'b0      ), // Optional inversion for D
                .IS_R_INVERTED(1'b0      )  // Optional inversion for R
            ) meta_0_inst (
                .C (CLK_DST        ), // 1-bit input: Clock
                .Q (meta_0_out[index]     ), // 1-bit output: Data
                .CE(1'b1           ), // 1-bit input: Clock enable
                .D (data_vector_src[index]), // 1-bit input: Data
                .R (1'b0           )  // 1-bit input: Synchronous reset
            );

            FDRE #(
                .INIT         (INIT_VALUE), // Initial value of register, 1'b0, 1'b1
                .IS_C_INVERTED(1'b0      ), // Optional inversion for C
                .IS_D_INVERTED(1'b0      ), // Optional inversion for D
                .IS_R_INVERTED(1'b0      )  // Optional inversion for R
            ) meta_1_inst (
                .C (CLK_DST   ), // 1-bit input: Clock
                .Q (meta_1_out[index]), // 1-bit output: Data
                .CE(1'b1      ), // 1-bit input: Clock enable
                .D (meta_0_out[index]), // 1-bit input: Data
                .R (1'b0      )  // 1-bit input: Synchronous reset
            );

            FDRE #(
                .INIT         (INIT_VALUE), // Initial value of register, 1'b0, 1'b1
                .IS_C_INVERTED(1'b0      ), // Optional inversion for C
                .IS_D_INVERTED(1'b0      ), // Optional inversion for D
                .IS_R_INVERTED(1'b0      )  // Optional inversion for R
            ) meta_2_inst (
                .C (CLK_DST   ), // 1-bit input: Clock
                .Q (meta_2_out[index]), // 1-bit output: Data
                .CE(1'b1      ), // 1-bit input: Clock enable
                .D (meta_1_out[index]), // 1-bit input: Data
                .R (1'b0      )  // 1-bit input: Synchronous reset
            );

            FDRE #(
                .INIT         (INIT_VALUE), // Initial value of register, 1'b0, 1'b1
                .IS_C_INVERTED(1'b0      ), // Optional inversion for C
                .IS_D_INVERTED(1'b0      ), // Optional inversion for D
                .IS_R_INVERTED(1'b0      )  // Optional inversion for R
            ) meta_3_inst (
                .C (CLK_DST   ), // 1-bit input: Clock
                .Q (meta_3_out[index]), // 1-bit output: Data
                .CE(1'b1      ), // 1-bit input: Clock enable
                .D (meta_2_out[index]), // 1-bit input: Data
                .R (1'b0      )  // 1-bit input: Synchronous reset
            );

            FDRE #(
                .INIT         (INIT_VALUE), // Initial value of register, 1'b0, 1'b1
                .IS_C_INVERTED(1'b0      ), // Optional inversion for C
                .IS_D_INVERTED(1'b0      ), // Optional inversion for D
                .IS_R_INVERTED(1'b0      )  // Optional inversion for R
            ) meta_4_inst (
                .C (CLK_DST   ), // 1-bit input: Clock
                .Q (DATA_OUT[index]  ), // 1-bit output: Data
                .CE(1'b1      ), // 1-bit input: Clock enable
                .D (meta_3_out[index]), // 1-bit input: Data
                .R (1'b0      )  // 1-bit input: Synchronous reset
            );
        end 
        endgenerate

endmodule
