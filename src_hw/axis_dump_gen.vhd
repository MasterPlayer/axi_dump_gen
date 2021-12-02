library IEEE;
    use IEEE.STD_LOGIC_1164.ALL;
    use ieee.std_logic_unsigned.all;
    use ieee.std_logic_arith.all;
    use IEEE.math_real."ceil";
    use IEEE.math_real."log2";

library UNISIM;
    use UNISIM.VComponents.all;

entity axis_dump_gen is
    generic (
        FREQ_HZ                 :           integer                         := 250000000        ;
        N_BYTES                 :           integer                         := 2                ;
        ASYNC                   :           boolean                         := false            ;
        SWAP_BYTES              :           boolean                         := false            ;
        MODE                    :           string                          := "SINGLE"          -- "SINGLE", "ZEROS", "BYTE"
    );
    port(
        CLK                     :   in      std_logic                                           ;
        RESET                   :   in      std_logic                                           ; 
        
        EVENT_START             :   in      std_logic                                           ;
        EVENT_STOP              :   in      std_Logic                                           ;
        IGNORE_READY            :   in      std_logic                                           ;
        STATUS                  :   out     std_logic                                           ;

        PAUSE                   :   in      std_logic_Vector ( 31 downto 0 )                    ;
        PACKET_SIZE             :   in      std_logic_Vector ( 31 downto 0 )                    ;
        PACKET_LIMIT            :   in      std_logic_Vector ( 31 downto 0 )                    ;

        VALID_COUNT             :   out     std_logic_vector ( 31 downto 0 )                    ;
        DATA_COUNT              :   out     std_logic_Vector ( 63 downto 0 )                    ;
        PACKET_COUNT            :   out     std_logic_Vector ( 63 downto 0 )                    ;

        M_AXIS_CLK              :   in      std_logic                                           ;
        M_AXIS_TDATA            :   out     std_logic_Vector ( (N_BYTES*8)-1 downto 0 )         ;
        M_AXIS_TKEEP            :   out     std_logic_Vector ( N_BYTES-1 downto 0 )             ;
        M_AXIS_TVALID           :   out     std_logic                                           ;
        M_AXIS_TREADY           :   in      std_logic                                           ;
        M_AXIS_TLAST            :   out     std_logic                                            
    );
end axis_dump_gen;



architecture axis_dump_gen_arch of axis_dump_gen is
    
    constant VERSION : string := "v2.1";
    
    ATTRIBUTE X_INTERFACE_INFO : STRING;
    ATTRIBUTE X_INTERFACE_INFO of RESET: SIGNAL is "xilinx.com:signal:reset:1.0 RESET RST";
    ATTRIBUTE X_INTERFACE_PARAMETER : STRING;
    ATTRIBUTE X_INTERFACE_PARAMETER of RESET: SIGNAL is "POLARITY ACTIVE_HIGH";

    constant    DATA_WIDTH      :           integer                             := (N_BYTES * 8);

    type fsm is (
        IDLE_ST                 ,
        PAUSE_ST                ,
        TX_ST                   
    );
    
    signal  current_state       :           fsm                                 := IDLE_ST          ;
    
    signal  pause_cnt           :           std_logic_Vector (  31 downto 0 )   := (others => '0')  ;
    signal  pause_reg           :           std_logic_Vector (  31 downto 0 )   := (others => '0')  ;

    signal  packet_limit_reg    :           std_logic_Vector ( 31 downto 0 )    := (others => '0')  ;
    signal  packet_limit_cnt    :           std_logic_Vector ( 31 downto 0 )    := x"00000001"  ;

    component fifo_out_async_xpm
        generic(
            DATA_WIDTH          :           integer         :=  256                         ;
            CDC_SYNC            :           integer         :=  4                           ;
            MEMTYPE             :           String          :=  "block"                     ;
            DEPTH               :           integer         :=  16                           
        );
        port(
            CLK                 :   in      std_logic                                       ;
            RESET               :   in      std_logic                                       ;        
            OUT_DIN_DATA        :   in      std_logic_Vector ( DATA_WIDTH-1 downto 0 )      ;
            OUT_DIN_KEEP        :   in      std_logic_Vector ( ( DATA_WIDTH/8)-1 downto 0 ) ;
            OUT_DIN_LAST        :   in      std_logic                                       ;
            OUT_WREN            :   in      std_logic                                       ;
            OUT_FULL            :   out     std_logic                                       ;
            OUT_AWFULL          :   out     std_logic                                       ;
            M_AXIS_CLK          :   in      std_logic                                       ;
            M_AXIS_TDATA        :   out     std_logic_Vector ( DATA_WIDTH-1 downto 0 )      ;
            M_AXIS_TKEEP        :   out     std_logic_Vector (( DATA_WIDTH/8)-1 downto 0 )  ;
            M_AXIS_TVALID       :   out     std_logic                                       ;
            M_AXIS_TLAST        :   out     std_logic                                       ;
            M_AXIS_TREADY       :   in      std_logic                                        
        );
    end component;

    component fifo_out_sync_xpm
        generic(
            DATA_WIDTH          :           integer         :=  256                         ;
            MEMTYPE             :           String          :=  "block"                     ;
            DEPTH               :           integer         :=  16                           
        );
        port(
            CLK                 :   in      std_logic                                       ;
            RESET               :   in      std_logic                                       ;        
            OUT_DIN_DATA        :   in      std_logic_Vector ( DATA_WIDTH-1 downto 0 )      ;
            OUT_DIN_KEEP        :   in      std_logic_Vector ( ( DATA_WIDTH/8)-1 downto 0 ) ;
            OUT_DIN_LAST        :   in      std_logic                                       ;
            OUT_WREN            :   in      std_logic                                       ;
            OUT_FULL            :   out     std_logic                                       ;
            OUT_AWFULL          :   out     std_logic                                       ;
            M_AXIS_TDATA        :   out     std_logic_Vector ( DATA_WIDTH-1 downto 0 )      ;
            M_AXIS_TKEEP        :   out     std_logic_Vector (( DATA_WIDTH/8)-1 downto 0 )  ;
            M_AXIS_TVALID       :   out     std_logic                                       ;
            M_AXIS_TLAST        :   out     std_logic                                       ;
            M_AXIS_TREADY       :   in      std_logic                                        
        );
    end component;

    signal  out_din_data        :           std_logic_vector ( DATA_WIDTH-1 downto 0 )      := (others => '0')      ;
    signal  out_din_keep        :           std_logic_vector ( ( DATA_WIDTH/8)-1 downto 0 ) := (others => '0')      ;
    signal  out_din_last        :           std_logic                                       := '0'                  ;
    signal  out_wren            :           std_logic                                       := '0'                  ;
    signal  out_full            :           std_logic                                                               ;
    signal  out_awfull          :           std_logic                                                               ;

    signal  packet_size_cnt     :           std_logic_vector (  31 downto 0 )               := (others => '0')  ;
    signal  cnt_vector          :           std_logic_Vector ( DATA_WIDTH-1 downto 0 )      := (others => '0');

    signal  packet_size_reg     :           std_logic_vector ( 31 downto 0 ) := (others => '0')         ;

    signal  timer               :           std_logic_Vector ( 31 downto 0 )            := (others => '0')  ;
    signal  valid_count_cnt     :           std_logic_vector ( 31 downto 0 )            := (others => '0')  ;
    signal  valid_count_reg     :           std_logic_Vector ( 31 downto 0 )            := (others => '0')  ;

    signal  status_reg          :           std_logic := '0';

    component bit_syncer_fdre 
        generic(
            DATA_WIDTH          :           integer := 32;
            INIT_VALUE          :           integer := 1 
        );
        port (
            CLK_SRC             :   in      std_logic                                   ;
            CLK_DST             :   in      std_logic                                   ;
            DATA_IN             :   in      std_logic_Vector ( DATA_WIDTH-1 downto 0 )  ;
            DATA_OUT            :   out     std_logic_Vector ( DATA_WIDTH-1 downto 0 )  
        );
    end component;

    signal  m_axis_tready_sig   :       std_logic ;
    signal  ignore_ready_m_axis_domain : std_Logic ;

    signal  event_stop_flaq     :           std_logic := '0';
    signal  write_accepted      :           std_Logic := '0';

    signal  data_count_reg      :           std_logic_vector ( 63 downto 0 ) := (others => '0');
    signal  packet_count_reg      :           std_logic_vector ( 63 downto 0 ) := (others => '0');


begin

    STATUS      <= status_reg;

    VALID_COUNT <= valid_count_reg;

    DATA_COUNT      <= data_count_reg;
    PACKET_COUNT    <= packet_count_reg;

    data_count_reg_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            case current_state is 
                when IDLE_ST => 
                    if EVENT_START = '1' then 
                        data_count_reg <= (others => '0');
                    else
                        data_count_reg <= data_count_reg;
                    end if;

                when others => 
                    if out_wren = '1' then 
                        data_count_reg <= data_count_reg + N_BYTES;
                    else
                        data_count_reg <= data_count_reg;
                    end if;
            end case;
        end if;
    end process;


    packet_count_reg_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            case current_state is 
                when IDLE_ST => 
                    if EVENT_START = '1' then 
                        packet_count_reg <= (others => '0');
                    else
                        packet_count_reg <= packet_count_reg;
                    end if;

                when others => 
                    if out_wren = '1' and out_din_last = '1' then 
                        packet_count_reg <= packet_count_reg + 1;
                    else
                        packet_count_reg <= packet_count_reg;
                    end if;

            end case;
        end if;
    end process;


    event_stop_flaq_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            case current_state is 
                when IDLE_ST => 
                    event_stop_flaq <= '0';

                when others => 
                    if EVENT_STOP = '1' then 
                        event_stop_flaq <= '1';
                    else
                        event_stop_flaq <= event_stop_flaq;
                    end if;

            end case;
        end if;
    end process;

    write_accepted <= not(out_awfull);

    timer_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            if timer < FREQ_HZ-1 then 
                timer <= timer + 1;
            else
                timer <= (others => '0');
            end if;
        end if;
    end process;

    valid_count_cnt_processing : process(CLK)
    begin 
        if CLK'event AND CLK = '1' then 
            if timer < FREQ_HZ-1 then 
                if out_wren = '1' then 
                    valid_count_cnt <= valid_count_cnt + 1;
                else
                    valid_count_cnt <= valid_count_cnt;
                end if;
            else
                valid_count_cnt <= (others => '0');
            end if;
        end if;
    end process;

    valid_count_reg_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            if timer < FREQ_HZ-1 then 
                valid_count_reg <= valid_count_reg;
            else
                if out_wren = '1' then 
                    valid_count_reg <= valid_count_cnt + 1;
                else
                    valid_count_reg <= valid_count_cnt;
                end if;
            end if;
        end if;
    end process;

    packet_limit_reg_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            if RESET = '1' then 
                packet_limit_reg <= (others => '0');
            else
                if EVENT_START = '1' then 
                    packet_limit_reg <= PACKET_LIMIT;
                else
                    packet_limit_reg <= packet_limit_reg;
                end if;
            end if;
        end if;
    end process;    

    packet_limit_cnt_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            if RESET = '1' then 
                packet_limit_cnt <= x"00000001";
            else

                case current_state is 
                    when IDLE_ST => 
                        packet_limit_cnt <= x"00000001";

                    when TX_ST => 
                        if EVENT_START = '1' then 
                            packet_limit_cnt <= x"00000001";
                        else
                            if write_accepted = '1' then 
                                if packet_size_cnt = packet_size_reg then
                                    if packet_limit_reg = 0 then 
                                        packet_limit_cnt <= x"00000001";
                                    else
                                        if packet_limit_cnt = packet_limit_reg then 
                                            packet_limit_cnt <= packet_limit_cnt;
                                        else
                                            packet_limit_cnt <= packet_limit_cnt + 1;
                                        end if;
                                    end if;
                                else
                                    packet_limit_cnt <= packet_limit_cnt;
                                end if;
                            else
                                packet_limit_cnt <= packet_limit_cnt;    
                            end if;
                        end if;

                    when others => 
                        packet_limit_cnt <= packet_limit_cnt;

                end case;
            end if;
        end if;
    end process;

    -- CHECK :: 
    -- Не отработается установка в TX_ST при PACKET_SIZE = 0, Надо проверить. 
    packet_size_reg_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            case current_state is

                when IDLE_ST => 
                    if write_accepted = '1' then 
                        packet_size_reg <= PACKET_SIZE-1;
                    else
                        packet_size_reg <= packet_size_reg;    
                    end if;

                when TX_ST => 
                    if write_accepted = '1' then 
                        if packet_size_cnt = packet_size_reg then
                            packet_size_reg <= PACKET_SIZE-1;
                        else
                            packet_size_reg <= packet_size_reg;
                        end if;
                    else
                        packet_size_reg <= packet_size_reg;    
                    end if;

                when others => 
                    packet_size_reg <= packet_size_reg;

            end case;
        end if;
    end process;



    pause_reg_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            if RESET = '1' then 
                pause_reg <= (others => '0');
            else
                case current_state is 
                    
                    when IDLE_ST =>
                        pause_reg <= PAUSE;

                    when TX_ST =>
                        if write_accepted = '1' then 
                            if packet_size_cnt = packet_size_reg then 
                                pause_reg <= PAUSE;    
                            else
                                pause_reg <= pause_reg;
                            end if;
                        else
                            pause_reg <= pause_reg;
                        end if;
                    
                    when others => 
                        pause_reg <= pause_reg;

                end case;
            end if;
        end if;
    end process;

    pause_cnt_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            if RESET = '1' then 
                pause_cnt <= x"00000001";
            else
                
                case current_state is
                
                    when PAUSE_ST =>
                        pause_cnt <= pause_cnt + 1;

                    when others =>  
                        pause_cnt <= x"00000001";
                
                end case ;
            end if;
        end if;
    end process;

    status_reg_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            case current_state is 
                when IDLE_ST => 
                    status_reg <= '0';

                when others => 
                    status_reg <= '1';
            
            end case;
        end if;
    end process;

    current_state_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            if RESET = '1' then 
                current_state <= IDLE_ST;
            else

                case current_state is

                    when IDLE_ST =>
                        if EVENT_START = '1' then 
                            if PACKET_SIZE /= 0 then 
                                if write_accepted = '1' then 
                                    if PAUSE = 0 then 
                                        current_state <= TX_ST;
                                    else
                                        current_state <= PAUSE_ST;
                                    end if;
                                else
                                    current_state <= current_state;
                                end if;
                            else
                                current_state <= current_state;
                            end if;
                        else
                            current_state <= current_state;
                        end if;

                    when PAUSE_ST =>
                        if pause_reg = 0 then 
                            current_state <= TX_ST;
                        else
                            if pause_cnt = pause_reg then 
                                current_state <= TX_ST;
                            else
                                current_state <= current_state;
                            end if;
                        end if;

                    when TX_ST =>
                        if write_accepted = '1' then 
                            if packet_size_cnt = packet_size_reg then 
                                if event_stop_flaq = '1' then 
                                    current_state <= IDLE_ST;
                                else
                                    if PACKET_SIZE = 0 then 
                                        current_state <= IDLE_ST;
                                    else
                                        if packet_limit_reg = 0 then  -- if no limits about packet limit count
                                            if pause_reg = 0 then 
                                                current_state <= current_state;
                                            else
                                                current_state <= PAUSE_ST;
                                            end if;
                                        else
                                            if packet_limit_cnt = packet_limit_reg then 
                                                current_state <= IDLE_ST;
                                            else
                                                if pause_reg = 0 then 
                                                    current_state <= current_state;
                                                else
                                                    current_state <= PAUSE_ST;
                                                end if;
                                            end if;
                                        end if;
                                    end if;
                                end if;
                            else
                                current_state <= current_state;
                            end if;
                        else
                            current_state <= current_state;
                        end if;

                    when others => 
                        current_state <= current_state;

                end case;
            end if;
        end if;
    end process;



    packet_size_cnt_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            if RESET = '1' then 
                packet_size_cnt <= (others => '0');
            else
                
                case current_state is

                    when TX_ST =>
                        if write_accepted = '1' then 
                            if packet_size_cnt = packet_size_reg then 
                                packet_size_cnt <= (others => '0');
                            else
                                packet_size_cnt <= packet_size_cnt + 1;
                            end if;
                        else
                            packet_size_cnt <= packet_size_cnt;
                        end if;

                    when others =>
                        packet_size_cnt <= (others => '0');

                end case;
            end if;
        end if;
    end process;



    GEN_ASYNC : if ASYNC = true generate 

        fifo_out_async_xpm_inst : fifo_out_async_xpm
            generic map (
                DATA_WIDTH      =>  DATA_WIDTH                                      ,
                CDC_SYNC        =>  4                                               ,
                MEMTYPE         =>  "distributed"                                   ,
                DEPTH           =>  16                                               
            )
            port map (
                CLK             =>  CLK                                             ,
                RESET           =>  RESET                                           ,
                
                OUT_DIN_DATA    =>  out_din_data                                    ,
                OUT_DIN_KEEP    =>  out_din_keep                                    ,
                OUT_DIN_LAST    =>  out_din_last                                    ,
                OUT_WREN        =>  out_wren                                        ,
                OUT_FULL        =>  out_full                                        ,
                OUT_AWFULL      =>  out_awfull                                      ,

                M_AXIS_CLK      =>  M_AXIS_CLK                                      ,
                M_AXIS_TDATA    =>  M_AXIS_TDATA                                    ,
                M_AXIS_TKEEP    =>  M_AXIS_TKEEP                                    ,
                M_AXIS_TVALID   =>  M_AXIS_TVALID                                   ,
                M_AXIS_TLAST    =>  M_AXIS_TLAST                                    ,
                M_AXIS_TREADY   =>  m_axis_tready_sig                                    
            );

        bit_syncer_fdre_inst : bit_syncer_fdre 
            generic map (
                DATA_WIDTH      =>  1                                               ,
                INIT_VALUE      =>  0                                                
            )
            port map (
                CLK_SRC         =>  CLK                                             ,
                CLK_DST         =>  M_AXIS_CLK                                      ,
                DATA_IN(0)      =>  IGNORE_READY                                    ,
                DATA_OUT(0)     =>  ignore_ready_m_axis_domain                       
            );

        m_axis_tready_sig <= '1' when ignore_ready_m_axis_domain = '1' else M_AXIS_TREADY;

    end generate;

    GEN_SYNC : if ASYNC = false generate 

        fifo_out_sync_xpm_inst : fifo_out_sync_xpm
            generic map (
                DATA_WIDTH      =>  DATA_WIDTH                                      ,
                MEMTYPE         =>  "distributed"                                   ,
                DEPTH           =>  16                                               
            )
            port map (
                CLK             =>  CLK                                             ,
                RESET           =>  RESET                                           ,
                
                OUT_DIN_DATA    =>  out_din_data                                    ,
                OUT_DIN_KEEP    =>  out_din_keep                                    ,
                OUT_DIN_LAST    =>  out_din_last                                    ,
                OUT_WREN        =>  out_wren                                        ,
                OUT_FULL        =>  out_full                                        ,
                OUT_AWFULL      =>  out_awfull                                      ,

                M_AXIS_TDATA    =>  M_AXIS_TDATA                                    ,
                M_AXIS_TKEEP    =>  M_AXIS_TKEEP                                    ,
                M_AXIS_TVALID   =>  M_AXIS_TVALID                                   ,
                M_AXIS_TLAST    =>  M_AXIS_TLAST                                    ,
                M_AXIS_TREADY   =>  m_axis_tready_sig                                    
            );

        m_axis_tready_sig <= '1' when IGNORE_READY = '1' else M_AXIS_TREADY;

    end generate;



    wren_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            if RESET = '1' then 
                out_wren <= '0';    
            else
                case current_state is
                    when TX_ST =>
                        if write_accepted = '1' then 
                            out_wren <= '1';
                        else
                            out_wren <= '0';
                        end if;

                    when others =>
                        out_wren <= '0';
                end case;
            end if;
        end if;
    end process;


    GEN_NO_SWAP : if SWAP_BYTES = false generate
        out_din_data <= cnt_vector;
    end generate;

    GEN_SWAP : if SWAP_BYTES = true generate
        GEN_LOOP_CYCLE : for i in 0 to N_BYTES-1 generate
            out_din_data( (((i+1)*8)-1) downto (i*8) ) <= cnt_vector((((N_BYTES*8)-1)-(i*8)) downto (((N_BYTES-1)*8)-(i*8)));
        end generate;
    end generate;





    out_din_keep <= (others => '1') ;



    last_field_processing : process(CLK)
    begin
        if CLK'event AND CLK = '1' then 
            if RESET = '1' then 
                out_din_last <= '0';
            else                
                case current_state is
                    when TX_ST =>
                        if (packet_size_cnt = packet_size_reg) then 
                            out_din_last <= '1';
                        else
                            out_din_last <= '0';
                        end if;
                        
                    when others =>
                        out_din_last <= out_din_last;

                end case;
            end if;
        end if;
    end process;


    -- Data vector presented as array of 8-bit counters
    GEN_BYTE_COUNTER : if MODE = "BYTE" generate

        gen_vector_cnt : for i in 0 to N_BYTES-1 generate 

            cnt_vector_processing : process(CLK)
            begin
                if CLK'event AND CLK = '1' then 
                    if RESET = '1' then 
                        cnt_vector( (((i+1)*8)-1) downto  (i*8)) <= conv_std_logic_Vector( ((256 - N_BYTES) + i) , 8);
                    else
                        case current_state is
                            when TX_ST =>
                                if write_accepted = '1' then 
                                    cnt_vector((((i+1)*8)-1) downto  (i*8)) <= cnt_vector((((i+1)*8)-1) downto  (i*8)) + conv_std_logic_Vector(N_BYTES, 8);
                                else
                                    cnt_vector((((i+1)*8)-1) downto  (i*8)) <= cnt_vector((((i+1)*8)-1) downto  (i*8));
                                end if;
                            when others =>
                                cnt_vector((((i+1)*8)-1) downto  (i*8)) <= cnt_vector((((i+1)*8)-1) downto  (i*8));
                        end case;
                    end if;
                end if;
            end process;
        end generate;

    end generate;

    -- Data word presented as simple counter, which width presented as (N_BYTES*8 downto 0) bits
    GEN_SIGNLE_COUNTER : if MODE = "SINGLE" generate

        cnt_vector_processing : process(CLK)
        begin
            if CLK'event AND CLK = '1' then 
                if RESET = '1' then 
                    cnt_vector <= (others => '0');
                else
                    if out_wren = '1' then 
                        cnt_vector <= cnt_vector + 1;
                    else
                        cnt_vector <= cnt_vector;
                    end if;
                end if;
            end if;
        end process;

    end generate;

    GEN_ZEROS_COUNTER : if MODE = "ZEROS" generate 
        cnt_vector <= (others => '0');
    end generate;


end axis_dump_gen_arch;
