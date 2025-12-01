`timescale 1ns / 1ps

// ==========================================================
// snn_layer.v (Ver 5.1 - Pipelined LIF 타이밍 수정)
// - 기능: 'lif_neuron'이 여러 사이클을 쓰도록 FSM 상태 분리
// ==========================================================
module snn_layer
#(
    parameter INPUT_DIM   = 20,
    parameter NUM_NEURONS = 128,
    parameter J_WIDTH     = 7,
    parameter W_ADDR_WIDTH = 12,
    parameter B_ADDR_WIDTH = 7,
    parameter W_MEM_FILE = "W1.mem",
    parameter B_MEM_FILE = "B1.mem",
    parameter [15:0] BETA_Q0_16      = 16'd62259,
    parameter signed [15:0] THRESHOLD_Q5_11 = 16'h0400,
    parameter LAYER_ID = 0
)
(
    input clk,
    input rst_n,
    input                      layer_start,
    input                      bram_clear,
    output reg                 layer_done,
    
    input      [(INPUT_DIM-1):0] spike_vector_in,
    output reg [(NUM_NEURONS-1):0] spike_buffer_out
);
    // --- FSM 상태 (수정됨) ---
    localparam STATE_IDLE           = 3'd0;
    localparam STATE_MEM_READ       = 3'd1; // 1. BRAM 읽기
    localparam STATE_CALC_START     = 3'd2; // 2. MAC 시작
    localparam STATE_CALC_WAIT_MAC  = 3'd3; // 3. MAC 완료 대기
    localparam STATE_CALC_WAIT_LIF  = 3'd4; // 4. 💡 LIF 완료 대기 (BRAM 쓰기 포함)
    localparam STATE_CHECK_J        = 3'd5; // 5. 다음 뉴런
    localparam STATE_DONE           = 3'd6; // 6. 완료
    
    // --- 레지스터 및 BRAM ---
    reg [2:0] state, next_state; // 💡 3비트로 변경
    reg [J_WIDTH-1:0] j_counter, next_j_counter;
    reg mac_start_pulse;
    reg [(NUM_NEURONS-1):0] next_spike_buffer_out;
    integer i;

    localparam MEM_WIDTH = 33;
    reg signed [MEM_WIDTH-1:0] mem_potential_bram [0:NUM_NEURONS-1];
    
    reg signed [MEM_WIDTH-1:0] mem_data_from_bram;
    wire signed [MEM_WIDTH-1:0] mem_data_to_bram;
    reg bram_write_enable;
    
    // --- 💡 LIF 제어 신호 추가 ---
    reg lif_start_pulse;
    wire lif_done_wire;

    // --- 인스턴스화 (수정) ---
    wire signed [15:0] w_data, b_data;
    wire [W_ADDR_WIDTH-1:0] w_addr;
    wire [B_ADDR_WIDTH-1:0] b_addr;
    wire        mac_done;
    wire signed [31:0] mac_cur_out;
    wire        lif_spk_out;
    wire        mac_busy;
    
    generic_rom #(.ADDR_WIDTH(W_ADDR_WIDTH), .INIT_FILE(W_MEM_FILE))
    rom_W ( .clk(clk), .addr(w_addr), .dout(w_data) );
    
    generic_rom #(.ADDR_WIDTH(B_ADDR_WIDTH), .INIT_FILE(B_MEM_FILE))
    rom_B ( .clk(clk), .addr(b_addr), .dout(b_data) );
    
    mac_unit #( .INPUT_DIM(INPUT_DIM), .J_WIDTH(J_WIDTH), .W_ADDR_WIDTH(W_ADDR_WIDTH), .B_ADDR_WIDTH(B_ADDR_WIDTH) )
    u_mac ( 
        .clk(clk), .rst_n(rst_n), .calc_start(mac_start_pulse), 
        .neuron_idx_in(j_counter), .spike_vector_in(spike_vector_in), 
        .rom_w_data_in(w_data), .rom_b_data_in(b_data), 
        .calc_done(mac_done), .busy(mac_busy), .cur_out(mac_cur_out), 
        .rom_w_addr_out(w_addr), .rom_b_addr_out(b_addr) 
    );
    
    // 💡 [수정] Pipelined LIF 인스턴스화
    lif_neuron #( .BETA_Q0_16(BETA_Q0_16), .THRESHOLD_Q5_11(THRESHOLD_Q5_11) )
    u_lif ( 
        .clk(clk), .rst_n(rst_n), 
        .lif_start(lif_start_pulse), // 💡 'mac_done' 대신 'lif_start'
        .lif_done(lif_done_wire),  // 💡 'lif_done'
        .cur_in(mac_cur_out), 
        .mem_in(mem_data_from_bram), 
        .mem_out(mem_data_to_bram), .spk_out(lif_spk_out) 
    );
    
    // ===================================
    // 4. 순차 로직 (BRAM) (동일)
    // ===================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= STATE_IDLE;
            j_counter        <= 0; 
            spike_buffer_out <= 0;
        end else begin
            state            <= next_state;
            j_counter        <= next_j_counter; 
            spike_buffer_out <= next_spike_buffer_out;

            // BRAM Read (1-cycle Latency)
            mem_data_from_bram <= mem_potential_bram[j_counter];

            // BRAM Write
            if (bram_write_enable) begin
                mem_potential_bram[j_counter] <= mem_data_to_bram;
            end
            
            // BRAM Clear
            if (bram_clear) begin
                for (i = 0; i < NUM_NEURONS; i = i + 1) begin 
                    mem_potential_bram[i] <= 0;
                end
            end
        end
    end

    // ===================================
    // 5. 조합 로직 (FSM) (수정됨)
    // ===================================
    always @(*) begin
        // 기본값
        next_state            = state;
        next_j_counter        = j_counter;
        next_spike_buffer_out = spike_buffer_out;
        
        mac_start_pulse   = 1'b0;
        lif_start_pulse   = 1'b0; // 💡 LIF 펄스 기본값
        bram_write_enable = 1'b0; 
        layer_done        = 1'b0;

        case (state)
            STATE_IDLE: begin
                if (layer_start) begin
                    next_j_counter        = 0;
                    next_spike_buffer_out = 0;
                    next_state            = STATE_MEM_READ;
                end
            end
            
            STATE_MEM_READ: begin
                // (BRAM이 'j_counter' 주소에서 mem_data_from_bram을 읽어오는 중)
                next_state = STATE_CALC_START;
            end
            
            STATE_CALC_START: begin
                mac_start_pulse = 1'b1;
                next_state      = STATE_CALC_WAIT_MAC;
            end
            
            // 💡 [수정] MAC과 LIF 대기 상태 분리
            STATE_CALC_WAIT_MAC: begin
                if (mac_done) begin
                    // MAC이 끝났으니, LIF 시작
                    lif_start_pulse = 1'b1;
                    next_state = STATE_CALC_WAIT_LIF;
                end
            end

            // 💡 [신설] LIF 대기 및 BRAM 쓰기 상태
            STATE_CALC_WAIT_LIF: begin
                if (lif_done_wire) begin
                    // LIF가 끝남
                    
                    // 디버깅 출력 (동일)
                    if ( LAYER_ID == 1 && j_counter == 0 ) begin
                        // $display(...)
                    end

                    // 스파이크 버퍼 업데이트 (동일)
                    if (lif_spk_out) begin
                        next_spike_buffer_out[j_counter] = 1'b1;
                    end
                    
                    // BRAM 쓰기 (LIF가 끝난 'mem_out' 값을 씀)
                    bram_write_enable = 1'b1;
                    
                    // 다음 상태로
                    next_state = STATE_CHECK_J;
                end
            end
            
            STATE_CHECK_J: begin
                if (j_counter == (NUM_NEURONS - 1)) begin
                    next_state = STATE_DONE;
                end else begin
                    next_j_counter = j_counter + 1;
                    next_state     = STATE_MEM_READ; // 💡 다음 뉴런 BRAM 읽기
                end
            end
            
            STATE_DONE: begin
                layer_done = 1'b1;
                next_state = STATE_IDLE;
            end
            
            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end
endmodule