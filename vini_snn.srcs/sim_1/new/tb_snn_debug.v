`timescale 1ns / 1ps

module tb_snn_debug();

    // ==========================================
    // 1. 신호 선언
    // ==========================================
    reg clk;
    reg rst_n;
    reg uart_rx_pin;
    wire uart_tx_pin;
    wire [3:0] leds;

    // 시뮬레이션 설정 (230400 bps)
    localparam BAUD_RATE  = 230400;
    localparam BIT_PERIOD = 1000000000 / BAUD_RATE; // 약 4340ns

    // ==========================================
    // 2. DUT 연결
    // ==========================================
    top_snn uut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_pin(uart_rx_pin),
        .uart_tx_pin(uart_tx_pin),
        .leds(leds)
    );

    // 100MHz 클럭 생성 (보드 입력과 동일)
    always #5 clk = ~clk; 

    // ==========================================
    // 3. UART 전송 Task
    // ==========================================
    task uart_send_byte(input [7:0] data);
        integer i;
        begin
            uart_rx_pin = 0; // Start Bit
            #(BIT_PERIOD);
            for (i=0; i<8; i=i+1) begin
                uart_rx_pin = data[i];
                #(BIT_PERIOD);
            end
            uart_rx_pin = 1; // Stop Bit
            #(BIT_PERIOD);
        end
    endtask

    // ==========================================
    // 4. 테스트 시나리오
    // ==========================================
    initial begin
        // 초기화
        clk = 0;
        rst_n = 1;
        uart_rx_pin = 1;

        // 리셋 (충분히 길게)
        #1000;
        rst_n = 0;
        #1000;
        rst_n = 1;
        #5000;

        $display("=== [Debug Simulation Start] ===");

        // ------------------------------------------------
        // 1. Start Command (0xAA)
        // ------------------------------------------------
        $display(">> Sending Start Command (0xAA)");
        uart_send_byte(8'hAA);
        
        #10000; // 상태 전환 대기

        // ------------------------------------------------
        // 2. 강력한 입력 전송 (All 1s vector)
        //    입력값: 20'hFFFFF (모든 뉴런 활성화)
        //    목적: 가중치가 로드되었다면 MAC 연산값이 최대로 커져야 함
        // ------------------------------------------------
        $display(">> Sending Step 1 Data (All 1s: 0xFF, 0xFF, 0x0F)");
        
        uart_send_byte(8'hFF); // Byte 1
        uart_send_byte(8'hFF); // Byte 2
        uart_send_byte(8'h0F); // Byte 3 (상위 4비트)
        
        // 데이터가 BRAM에 들어가고 -> 연산이 시작될 때까지 대기
        // (UART 수신 + BRAM Write + SNN Core Start까지 시간이 좀 걸림)
        
        $display(">> Waiting for computation...");
        #500000; // 충분히 기다리며 Waveform 관찰
        
        $display("=== [Simulation End] Check Waveform! ===");
        $finish;
    end

endmodule