`timescale 1ns / 1ps



module axis_dump_gen_nc #(
    parameter integer FREQ_HZ    = 250000000,
    parameter integer N_BYTES    = 2        ,
    parameter integer ASYNC      = 1'b0     ,
    parameter integer SWAP_BYTES = 1'b0     ,
    parameter string  MODE       = "SINGLE" , 
    parameter integer NUMBER_OF_COUNTERS = 2 
) (
    input  logic                   CLK          ,
    input  logic                   RESET        ,
    input  logic                   EVENT_START  ,
    input  logic                   EVENT_STOP   ,
    input  logic                   IGNORE_READY ,
    output logic                   STATUS       ,
    input  logic [           31:0] PAUSE        ,
    input  logic [           31:0] PACKET_SIZE  ,
    input  logic [           31:0] PACKET_LIMIT ,
    output logic [           31:0] VALID_COUNT  ,
    output logic [           63:0] DATA_COUNT   ,
    output logic [           63:0] PACKET_COUNT ,
    input  logic                   M_AXIS_CLK   ,
    output logic [(N_BYTES*8)-1:0] M_AXIS_TDATA ,
    output logic [    N_BYTES-1:0] M_AXIS_TKEEP ,
    output logic                   M_AXIS_TVALID,
    input  logic                   M_AXIS_TREADY,
    output logic                   M_AXIS_TLAST
);
    
    parameter string VERSION = "v2.2";
    parameter integer DATA_WIDTH = (N_BYTES * 8);
    parameter integer DATA_WIDTH_CNT = (N_BYTES/NUMBER_OF_COUNTERS)*8;

    
    // ATTRIBUTE X_INTERFACE_INFO : STRING;
    // ATTRIBUTE X_INTERFACE_INFO of RESET: SIGNAL is "xilinx.com:signal:reset:1.0 RESET RST";
    // ATTRIBUTE X_INTERFACE_PARAMETER : STRING;
    // ATTRIBUTE X_INTERFACE_PARAMETER of RESET: SIGNAL is "POLARITY ACTIVE_HIGH";


    typedef enum {
        IDLE_ST     ,
        PAUSE_ST    ,
        TX_ST
    } fsm;

    fsm                        current_state    = IDLE_ST     ;
    logic [              31:0] pause_cnt        = '{default:0};
    logic [              31:0] pause_reg        = '{default:0};
    logic [              31:0] packet_limit_reg = '{default:0};
    logic [              31:0] packet_limit_cnt = 'd1         ;
    logic [    DATA_WIDTH-1:0] out_din_data     = '{default:0};
    logic [(DATA_WIDTH/8)-1:0] out_din_keep     = '{default:0};
    logic                      out_din_last     = 1'b0        ;
    logic                      out_wren         = 1'b0        ;
    logic                      out_full                       ;
    logic                      out_awfull                     ;
    logic [              31:0] packet_size_cnt  = '{default:0};

    logic [NUMBER_OF_COUNTERS-1:0][DATA_WIDTH_CNT-1:0] cnt_vector = '{default:0};

    logic [31:0] packet_size_reg = '{default:0};
    logic [31:0] timer           = '{default:0};

    logic [31:0] valid_count_cnt = '{default:0};

    logic m_axis_tready_sig;

    logic ignore_ready_m_axis_domain;

    logic event_stop_flaq = 1'b0;
    logic write_accepted  = 1'b0;

    logic [              63:0] packet_count_reg           = '{default:0};


    initial begin : drc_check

        reg drc_error;
        drc_error = 0;

        $display("[%s] : width of each counter : %0d", "AXIS_DUMP_GEN_SV", DATA_WIDTH_CNT);

        if (MODE != "DATA") begin 
            if (MODE != "ZEROS") begin 
                $error("[%s %0d-%0d] Supported mode only for ZEROS or DATA, but not %s", "AXIS_PACKETIZER", 1, 1, MODE);
                drc_error = 1;                    
            end 
        end 

        if (N_BYTES % NUMBER_OF_COUNTERS != 0) begin 
            $error("[%s %0d-%0d] Assymetric counters and data bus width : DATA width : %0d, Number of Counters %0d", "AXIS_PACKETIZER", 1, 2, N_BYTES, NUMBER_OF_COUNTERS);
           drc_error = 1;                                
        end 
           

        if (drc_error)
            #1 $finish;
    end 

    always_ff @(posedge CLK) begin : data_count_reg_processing
        case (current_state)
            IDLE_ST: 
                if (EVENT_START) begin 
                    DATA_COUNT <= '{default:0};
                end else begin 
                    DATA_COUNT <= DATA_COUNT;
                end

            default :  
                if (out_wren) begin 
                    DATA_COUNT <= DATA_COUNT + N_BYTES;
                end else begin 
                    DATA_COUNT <= DATA_COUNT;
                end
        endcase
    end



    always_ff @(posedge CLK) begin : packet_count_reg_processing
        case (current_state) 
            IDLE_ST: 
                if (EVENT_START) begin 
                    PACKET_COUNT <= '{default:0};
                end else begin 
                    PACKET_COUNT <= PACKET_COUNT;
                end

            default :  
                if (out_wren & out_din_last) begin 
                    PACKET_COUNT <= PACKET_COUNT + 1;
                end else begin 
                    PACKET_COUNT <= PACKET_COUNT;
                end

        endcase
    end



    always_ff @(posedge CLK) begin : event_stop_flaq_processing
        case (current_state) 
            IDLE_ST: 
                event_stop_flaq <= 'b0;

            default :  
                if (EVENT_STOP) begin 
                    event_stop_flaq <= 1'b1;
                end else begin 
                    event_stop_flaq <= event_stop_flaq;
                end

        endcase
    end


    always_comb begin 
        write_accepted = ~out_awfull;
    end 



    always_ff @(posedge CLK) begin : timer_processing
        if (timer < FREQ_HZ-1) begin  
            timer <= timer + 1;
        end else begin 
            timer <= '{default:0};
        end
    end



    always_ff @(posedge CLK) begin : valid_count_cnt_processing
        if (timer < (FREQ_HZ-1)) begin  
            if (out_wren) begin 
                valid_count_cnt <= valid_count_cnt + 1;
            end else begin
                valid_count_cnt <= valid_count_cnt;
            end
        end else begin 
            valid_count_cnt <= '{default:0};
        end
    end



    always_ff @(posedge CLK) begin : VALID_COUNT_processing
        if (timer < (FREQ_HZ-1)) begin  
            VALID_COUNT <= VALID_COUNT;
        end else begin 
            if (out_wren) begin 
                VALID_COUNT <= valid_count_cnt + 1;
            end else begin
                VALID_COUNT <= valid_count_cnt;
            end
        end
    end



    always_ff @(posedge CLK) begin : packet_limit_reg_processing
        if (RESET) begin 
            packet_limit_reg <= '{default:0};
        end else begin 
            if (EVENT_START) begin 
                packet_limit_reg <= PACKET_LIMIT;
            end else begin 
                packet_limit_reg <= packet_limit_reg;
            end
        end
    end



    always_ff @(posedge CLK) begin : packet_limit_cnt_processing
        if (RESET) begin 
            packet_limit_cnt <= 'd1;
        end else begin 
            case (current_state) 
                IDLE_ST: 
                    packet_limit_cnt <= 'd1;

                TX_ST: 
                    if (EVENT_START) begin 
                        packet_limit_cnt <= 'd1;
                    end else begin 
                        if (write_accepted) begin 
                            if (packet_size_cnt == packet_size_reg) begin 
                                if (~packet_limit_reg) begin 
                                    packet_limit_cnt <= 'd1;
                                end else begin 
                                    if (packet_limit_cnt == packet_limit_reg) begin 
                                        packet_limit_cnt <= packet_limit_cnt;
                                    end else begin 
                                        packet_limit_cnt <= packet_limit_cnt + 1;
                                    end
                                end
                            end else begin 
                                packet_limit_cnt <= packet_limit_cnt;
                            end
                        end else begin 
                            packet_limit_cnt <= packet_limit_cnt;    
                        end
                    end

                default :  
                    packet_limit_cnt <= packet_limit_cnt;

            endcase
        end
    end



    always_ff @(posedge CLK) begin : packet_size_reg_processing
        case (current_state)

            IDLE_ST: 
                if (write_accepted) begin  
                    packet_size_reg <= (PACKET_SIZE-1);
                end else begin 
                    packet_size_reg <= packet_size_reg;    
                end

            TX_ST: 
                if (write_accepted) begin 
                    if (packet_size_cnt == packet_size_reg) begin 
                        packet_size_reg <= (PACKET_SIZE-1);
                    end else begin 
                        packet_size_reg <= packet_size_reg;
                    end
                end else begin 
                    packet_size_reg <= packet_size_reg;    
                end

            default :  
                packet_size_reg <= packet_size_reg;

        endcase
    end



    always_ff @(posedge CLK) begin : pause_reg_processing
        if (RESET) begin 
            pause_reg <= '{default:0};
        end else begin 
            case (current_state) 
                IDLE_ST:
                    pause_reg <= PAUSE;

                TX_ST:
                    if (write_accepted) begin  
                        if (packet_size_cnt == packet_size_reg) begin 
                            pause_reg <= PAUSE;    
                        end else begin 
                            pause_reg <= pause_reg;
                        end
                    end else begin 
                        pause_reg <= pause_reg;
                    end
                
                default :  
                    pause_reg <= pause_reg;

            endcase
        end
    end



    always_ff @(posedge CLK) begin : pause_cnt_processing
        if (RESET) begin 
            pause_cnt <= 'd1;
        end else begin 
            case (current_state)
                PAUSE_ST:
                    pause_cnt <= pause_cnt + 1;

                default :   
                    pause_cnt <= 'd1;
            
            endcase
        end
    end



    always_ff @(posedge CLK) begin : status_reg_processing
        case (current_state) 
            IDLE_ST: 
                STATUS <= 1'b0;

            default :  
                STATUS <= 1'b1;
        
        endcase
    end



    always_ff @(posedge CLK) begin : current_state_processing
        if (RESET) begin 
            current_state <= IDLE_ST;
        end else begin 

            case (current_state)

                IDLE_ST:
                    if (EVENT_START) begin 
                        if (PACKET_SIZE != 0) begin  
                            if (write_accepted) begin 
                                if (PAUSE == 0) begin 
                                    current_state <= TX_ST;
                                end else begin 
                                    current_state <= PAUSE_ST;
                                end
                            end else begin 
                                current_state <= current_state;
                            end
                        end else begin 
                            current_state <= current_state;
                        end
                    end else begin 
                        current_state <= current_state;
                    end

                PAUSE_ST:
                    if (pause_reg == 0) begin  
                        current_state <= TX_ST;
                    end else begin 
                        if (pause_cnt == pause_reg) begin  
                            current_state <= TX_ST;
                        end else begin 
                            current_state <= current_state;
                        end
                    end

                TX_ST:
                    if (write_accepted) begin 
                        if (packet_size_cnt == packet_size_reg) begin 
                            if (event_stop_flaq) begin  
                                current_state <= IDLE_ST;
                            end else begin 
                                if (PACKET_SIZE == 0) begin 
                                    current_state <= IDLE_ST;
                                end else begin 
                                    if (packet_limit_reg == 0) begin 
                                        if (pause_reg == 0) begin 
                                            current_state <= current_state;
                                        end else begin 
                                            current_state <= PAUSE_ST;
                                        end
                                    end else begin 
                                        if (packet_limit_cnt == packet_limit_reg) begin 
                                            current_state <= IDLE_ST;
                                        end else begin 
                                            if (pause_reg == 0) begin  
                                                current_state <= current_state;
                                            end else begin 
                                                current_state <= PAUSE_ST;
                                            end
                                        end
                                    end
                                end
                            end
                        end else begin 
                            current_state <= current_state;
                        end
                    end else begin 
                        current_state <= current_state;
                    end

                default :  
                    current_state <= current_state;

            endcase
        end
    end



    always_ff @(posedge CLK) begin : packet_size_cnt_processing 
        if (RESET) begin 
            packet_size_cnt <= '{default:0};
        end else begin 
            
            case (current_state)
                TX_ST:
                    if (write_accepted) begin  
                        if (packet_size_cnt == packet_size_reg) begin
                            packet_size_cnt <= '{default:0};
                        end else begin 
                            packet_size_cnt <= packet_size_cnt + 1;
                        end
                    end else begin 
                        packet_size_cnt <= packet_size_cnt;
                    end

                default : 
                    packet_size_cnt <= '{default:0};

            endcase
        end
    end

    generate 

        if (ASYNC == 1) begin : GEN_ASYNC

            fifo_out_async_xpm #(
                .DATA_WIDTH(DATA_WIDTH   ),
                .CDC_SYNC  (4            ),
                .MEMTYPE   ("distributed"),
                .DEPTH     (16           )
            ) fifo_out_async_xpm_inst (
                .CLK          (CLK              ),
                .RESET        (RESET            ),
                .OUT_DIN_DATA (out_din_data     ),
                .OUT_DIN_KEEP (out_din_keep     ),
                .OUT_DIN_LAST (out_din_last     ),
                .OUT_WREN     (out_wren         ),
                .OUT_FULL     (out_full         ),
                .OUT_AWFULL   (out_awfull       ),
                .M_AXIS_CLK   (M_AXIS_CLK       ),
                .M_AXIS_TDATA (M_AXIS_TDATA     ),
                .M_AXIS_TKEEP (M_AXIS_TKEEP     ),
                .M_AXIS_TVALID(M_AXIS_TVALID    ),
                .M_AXIS_TLAST (M_AXIS_TLAST     ),
                .M_AXIS_TREADY(m_axis_tready_sig)
            );

            bit_syncer_fdre #(
                .DATA_WIDTH(1),
                .INIT_VALUE(0)
            ) bit_syncer_fdre_inst (
                .CLK_SRC (CLK                       ),
                .CLK_DST (M_AXIS_CLK                ),
                .DATA_IN (IGNORE_READY              ),
                .DATA_OUT(ignore_ready_m_axis_domain)
            );

            always_comb begin 
                if (ignore_ready_m_axis_domain) begin 
                    m_axis_tready_sig = 1'b1; 
                end else begin  
                    m_axis_tready_sig = M_AXIS_TREADY;
                end 
            end 

        end 

        if (ASYNC == 0) begin : GEN_SYNC


            fifo_out_sync_xpm #(
                .DATA_WIDTH(DATA_WIDTH   ),
                .MEMTYPE   ("distributed"),
                .DEPTH     (16           )
            ) fifo_out_sync_xpm_inst (
                .CLK          (CLK              ),
                .RESET        (RESET            ),
                .OUT_DIN_DATA (out_din_data     ),
                .OUT_DIN_KEEP (out_din_keep     ),
                .OUT_DIN_LAST (out_din_last     ),
                .OUT_WREN     (out_wren         ),
                .OUT_FULL     (out_full         ),
                .OUT_AWFULL   (out_awfull       ),
                .M_AXIS_TDATA (M_AXIS_TDATA     ),
                .M_AXIS_TKEEP (M_AXIS_TKEEP     ),
                .M_AXIS_TVALID(M_AXIS_TVALID    ),
                .M_AXIS_TLAST (M_AXIS_TLAST     ),
                .M_AXIS_TREADY(m_axis_tready_sig)
            );

            always_comb begin 
                if (ignore_ready_m_axis_domain) begin 
                    m_axis_tready_sig = 1'b1; 
                end else begin  
                    m_axis_tready_sig = M_AXIS_TREADY;
                end 
            end 

        end

        if (SWAP_BYTES == 0) begin : GEN_NO_SWAP
            always_comb begin 
                out_din_data = cnt_vector;
            end 
        end 

        if (SWAP_BYTES == 1) begin : GEN_SWAP
            for ( genvar i = 0; i < N_BYTES; i++) begin : GEN_LOOP_CYCLE
                always_comb begin 
                    out_din_data[(((i+1)*8)-1):(i*8)] = cnt_vector[(((N_BYTES*8)-1)-(i*8)) : (((N_BYTES-1)*8)-(i*8))];
                end 
            end
        end 

        if (MODE == "DATA") begin : GEN_BYTE_COUNTER

            for (genvar cnt_index = 0; cnt_index < NUMBER_OF_COUNTERS; cnt_index++) begin 
                // for (genvar i = 0; i < DATA_WIDTH_CNT/8; i++) begin : GEN_VECTOR_CNT 

                always_ff @(posedge CLK) begin : cnt_vector_processing 
                    if (RESET) begin 
                        cnt_vector[cnt_index] <= ((2**DATA_WIDTH_CNT) - NUMBER_OF_COUNTERS) + cnt_index;
                    end else begin 
                        case (current_state)
                            TX_ST:
                                if (write_accepted) begin 
                                    cnt_vector[cnt_index] <= cnt_vector[cnt_index] + NUMBER_OF_COUNTERS;
                                end else begin 
                                    cnt_vector[cnt_index] <= cnt_vector[cnt_index];
                                end
                            default : 
                                cnt_vector[cnt_index] <= cnt_vector[cnt_index];
                        endcase
                    end
                end
            end 
        end

        if (MODE == "ZEROS") begin : GEN_ZEROS_COUNTER 
    
            always_comb begin 
                cnt_vector = '{default:0};
            end
    

        end 

    endgenerate 



    always_ff @(posedge CLK) begin : wren_processing 
        if (RESET) begin 
            out_wren <= 1'b0;    
        end else begin 
            case (current_state)
                TX_ST:
                    if (write_accepted) begin  
                        out_wren <= 1'b1;
                    end else begin 
                        out_wren <= 1'b0;
                    end

                default : 
                    out_wren <= 1'b0;
            endcase
        end
    end

    always_comb begin 
        out_din_keep = '{default:1};
    end 


    always_ff @(posedge CLK) begin : last_field_processing 
        if (RESET) begin 
            out_din_last <= 1'b0;
        end else begin                 
            case (current_state)
                TX_ST:
                    if (packet_size_cnt == packet_size_reg) begin  
                        out_din_last <= 1'b1;
                    end else begin 
                        out_din_last <= 1'b0;
                    end
                    
                default : 
                    out_din_last <= out_din_last;

            endcase
        end
    end




endmodule
