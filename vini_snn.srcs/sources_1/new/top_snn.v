`timescale 1ns / 1ps

module top_snn
(
    input clk,         // 100MHz 클럭 (보드 E3)
    input rst_n,       // 리셋 (Active Low)
    input uart_rx_pin, // PC -> FPGA (Rx)
    output uart_tx_pin, // FPGA -> PC (Tx)
    output reg [3:0] leds // 상태 표시 LED
);

    // ====================================================
    // 0. Clock Wizard (100MHz -> 50MHz)
    // ====================================================
    wire clk_50mhz;
    wire locked; 
    
    clk_wiz_0 u_clk_wiz (
        .clk_out1(clk_50mhz),     
        .resetn(rst_n),           
        .locked(locked),          
        .clk_in1(clk)             
    );

    // ====================================================
    // 1. 파라미터 및 전역 신호
    // ====================================================
    localparam T_MAX = 3000;
    localparam N_MELS = 20;
    
    wire rst = (rst_n == 1'b0); // Active High 변환

    // ====================================================
    // 2. UART 모듈 (💡 50MHz 파라미터 적용 필수!)
    // ====================================================
    wire [7:0] rx_byte_wire;
    wire       rx_done_wire;
    
    // 💡 [수정] #(.CLK_FREQ(50_000_000)) 추가됨
    uart_rx u_uart_rx (
        .clk(clk_50mhz), 
        .rst(rst), 
        .Rx_Serial(uart_rx_pin), 
        .Rx_Done(rx_done_wire), 
        .Rx_Out(rx_byte_wire)
    );

    reg  [7:0] tx_byte_reg;
    reg        tx_start_reg;
    wire       tx_done_wire;

    // 💡 [수정] #(.CLK_FREQ(50_000_000)) 추가됨
    uart_tx u_uart_tx (
        .clk(clk_50mhz), 
        .rst(rst), 
        .start(tx_start_reg), 
        .Byte_To_Send(tx_byte_reg), 
        .Tx_Serial(uart_tx_pin), 
        .Tx_Done(tx_done_wire)
    );

    // ====================================================
    // 3. SNN 코어 연결
    // ====================================================
    wire [15:0] core_spk_alexa_wire;
    wire [15:0] core_spk_neg_wire;
    reg  core_start_inference_reg;
    reg  [N_MELS-1:0] core_spike_input_reg;
    wire core_led_out_wire;
    wire [3:0]  core_t_state_wire;
    wire [11:0] core_t_count_wire;

    snn_core uut_snn_core (
        .clk(clk_50mhz),
        .rst_n(rst_n), 
        .start_inference(core_start_inference_reg),
        .uart_spike_vector(core_spike_input_reg),
        .led_out(core_led_out_wire),
        .debug_t_state(core_t_state_wire),
        .debug_t_count(core_t_count_wire),
        .debug_spk_alexa(core_spk_alexa_wire),
        .debug_spk_neg(core_spk_neg_wire)
    );

    localparam T_STATE_INIT    = 4'd1;
    localparam T_STATE_CHECK_T = 4'd9; 
    localparam T_STATE_DECIDE  = 4'd10; 

    // ====================================================
    // 4. BRAM (Spike Storage)
    // ====================================================
    reg [N_MELS-1:0] spike_storage_bram [0:T_MAX-1];
    reg [11:0] bram_write_addr_reg;
    reg [N_MELS-1:0] bram_data_in_reg;
    reg bram_write_en_reg;

    always @(posedge clk_50mhz) begin
        if (bram_write_en_reg) begin
            spike_storage_bram[bram_write_addr_reg] <= bram_data_in_reg;
        end
    end
    
    // ====================================================
    // 5. 스파이크 공급기
    // ====================================================
    always @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            core_spike_input_reg <= 0;
        end else begin
            if (core_t_state_wire == T_STATE_INIT) begin
                core_spike_input_reg <= spike_storage_bram[0]; 
            end 
            else if (core_t_state_wire == T_STATE_CHECK_T) begin
                if (core_t_count_wire < (T_MAX - 1)) begin
                    core_spike_input_reg <= spike_storage_bram[core_t_count_wire + 1]; 
                end
            end
        end
    end

    // ====================================================
    // 6. Top FSM (수정됨: UART Start Logic Fix)
    // ====================================================
    reg [2:0] state, next_state;
    localparam FSM_IDLE         = 3'd0;
    localparam FSM_RECEIVE_B1   = 3'd1;
    localparam FSM_RECEIVE_B2   = 3'd2;
    localparam FSM_RECEIVE_B3   = 3'd3;
    localparam FSM_COMPUTE_START = 3'd4;
    localparam FSM_COMPUTING     = 3'd5;
    localparam FSM_SEND_RESULT   = 3'd6;
    
    reg [N_MELS-1:0] rx_vector_buf;

    // --- FSM 1: 순차 로직 ---
    always @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            state <= FSM_IDLE;
            bram_write_addr_reg <= 0;
            leds <= 4'b0001;
            tx_start_reg <= 0;
            rx_vector_buf <= 0;
            bram_write_en_reg <= 0;
        end else begin
            state <= next_state;
            
            // Pulse 신호 초기화
            bram_write_en_reg <= 0; 
            
            // 💡 [수정] UART Start 로직을 case문 밖으로 뺐습니다.
            // 상태가 'SEND_RESULT'로 바뀌는 그 순간(Edge)에 1을 쏩니다.
            if (next_state == FSM_SEND_RESULT && state != FSM_SEND_RESULT) begin
                tx_start_reg <= 1'b1;
            end else begin
                tx_start_reg <= 0;
            end

            case(state)
                FSM_IDLE: begin
                    leds <= 4'b0001;
                    if (rx_done_wire && rx_byte_wire == 8'hAA) begin
                         bram_write_addr_reg <= 0;
                    end
                end

                FSM_RECEIVE_B1: begin 
                    leds <= 4'b0010;
                    if (rx_done_wire) rx_vector_buf[7:0] <= rx_byte_wire;
                end
                
                FSM_RECEIVE_B2: begin
                    leds <= 4'b0010;
                    if (rx_done_wire) rx_vector_buf[15:8] <= rx_byte_wire;
                end

                FSM_RECEIVE_B3: begin 
                    leds <= 4'b0010;
                    if (rx_done_wire) begin
                        rx_vector_buf[19:16] <= rx_byte_wire[3:0];
                        
                        bram_data_in_reg <= {rx_byte_wire[3:0], rx_vector_buf[15:8], rx_vector_buf[7:0]}; 
                        bram_write_en_reg <= 1'b1; 
                        
                        if (bram_write_addr_reg < T_MAX - 1) 
                             bram_write_addr_reg <= bram_write_addr_reg + 1;
                        else 
                             bram_write_addr_reg <= 0; 
                    end
                end

                FSM_COMPUTE_START: leds <= 4'b0100;
                FSM_COMPUTING:     leds <= 4'b1000;
                FSM_SEND_RESULT:   leds <= 4'b1100;
                default:           leds <= 4'b1111;
            endcase
        end
    end

    // --- FSM 2: 조합 로직 ---
    always @(*) begin
        next_state = state;
        core_start_inference_reg = 1'b0;
        tx_byte_reg = 8'h00; 

        if (core_led_out_wire) tx_byte_reg = 8'hA1;
        else                   tx_byte_reg = 8'hB0;
        
        if (state == FSM_COMPUTE_START) core_start_inference_reg = 1'b1;

        case (state)
            FSM_IDLE: begin
                if (rx_done_wire && rx_byte_wire == 8'hAA) next_state = FSM_RECEIVE_B1;
            end
            FSM_RECEIVE_B1: if (rx_done_wire) next_state = FSM_RECEIVE_B2;
            FSM_RECEIVE_B2: if (rx_done_wire) next_state = FSM_RECEIVE_B3;
            FSM_RECEIVE_B3: begin
                if (rx_done_wire) begin
                    if (bram_write_addr_reg == (T_MAX - 1)) next_state = FSM_COMPUTE_START;
                    else                                    next_state = FSM_RECEIVE_B1;
                end
            end
            FSM_COMPUTE_START: next_state = FSM_COMPUTING;
            FSM_COMPUTING: begin
                if (core_t_state_wire == T_STATE_DECIDE) next_state = FSM_SEND_RESULT;
            end
            FSM_SEND_RESULT: begin
                if (tx_done_wire) next_state = FSM_IDLE;
            end
            default: next_state = FSM_IDLE;
        endcase
    end

endmodule