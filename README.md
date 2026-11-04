# FPGA SPI Master/Slave

Vivado 2020.2 기반 Basys3 FPGA 프로젝트입니다. 현재 저장소에는 SPI Slave와 HC-SR04 거리 측정 결과를 UART로 출력하는 별도 경로가 있습니다.

## SPI Slave

`slave/src/spi_slave.v`는 SPI Mode 0, MSB 우선 8비트 전송을 처리합니다. `STATUS` (`8'h10`)에는 `8'h01`, `SEND` (`8'h20`)에는 `8'hA5`, 그 외 명령에는 `8'h00`을 응답합니다. 명령 전송 후 Dummy 1바이트로 응답을 읽습니다. 테스트벤치는 `slave/sim/tb_spi_slave_test.v`에 있습니다.

## HC-SR04 → UART

`slave/src/top.v`의 `top_sensor`는 100 MHz 클럭에서 1 µs enable을 만들고, 100 ms마다 측정을 시작합니다. Trig는 10 µs이며 Echo 상승 대기와 HIGH 측정은 각각 30 ms로 제한합니다. HIGH 시간을 58로 나눈 정수 cm 값 중 2~400 cm를 정상으로 판정합니다.

측정 결과는 최신값 버퍼와 4건 깊이의 FIFO를 거쳐 115200 bps, 8N1 UART로 출력됩니다. 출력 형식은 `DIST=0123 cm, OK\r\n`이며 오류 상태는 `NO_ECHO`, `ECHO_TIMEOUT`, `RANGE_ERROR`로 표시됩니다.

이 UART 경로는 현재 SPI Slave와 연결되지 않았습니다. 기존 `slave/constraints/Basys3-Master_orginal.xdc`도 SPI Slave용 핀 설정이므로 `top_sensor` 보드 사용에는 별도 핀 제약이 필요합니다.
