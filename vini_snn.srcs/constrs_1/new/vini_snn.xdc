## =========================================================
## 1. Clock signal (Nexys A7)
## - Pin E3: 100MHz 온보드 클럭
## =========================================================
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk }]; 
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }];


## =========================================================
## 2. Reset (Active Low)
## - Pin C12: 'CPU_RESETN' (빨간색 버튼)
## - Nexys A7에는 Active Low 전용 리셋 버튼이 있어서 이걸 씁니다.
## - 버튼을 누르면 rst_n = 0 (리셋), 떼면 rst_n = 1 (동작)
## =========================================================
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { rst_n }];


## =========================================================
## 3. UART (USB-RS232)
## - Pin C4: FPGA Rx (PC에서 보낸 데이터를 받음)
## - Pin D4: FPGA Tx (PC로 데이터를 보냄)
## =========================================================
set_property -dict { PACKAGE_PIN C4    IOSTANDARD LVCMOS33 } [get_ports { uart_rx_pin }];
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { uart_tx_pin }];


## =========================================================
## 4. LEDs (상태 표시)
## - Pin H17 ~ N14: 보드 우측 하단의 초록색 LED 0~3번
## =========================================================
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { leds[0] }]; # LED 0
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { leds[1] }]; # LED 1
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { leds[2] }]; # LED 2
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { leds[3] }]; # LED 3


## =========================================================
## 5. Configuration Options
## =========================================================
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]