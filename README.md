# FPGA SPI Master/Slave

Vivado 2020.2 기반 FPGA SPI 통신 프로젝트입니다.

## 현재 구성

- `slave/src/spi_slave.v`: SPI Mode 0, MSB 우선의 8비트 Slave 모듈
- `slave/sim/tb_spi_slave_test.v`: 명령, 연속 전송, CS 중단을 확인하는 테스트벤치
- `master/`: Master RTL을 추가할 디렉터리
- `*/constraints/`: Basys3 제약 파일

## Slave 명령

| 명령 | 값 | 응답 |
| --- | --- | --- |
| STATUS | `8'h10` | `8'h01` (READY) |
| SEND | `8'h20` | `8'hA5` |
| 그 외 | 기타 값 | `8'h00` |

명령 1바이트를 전송한 뒤 Dummy 1바이트를 전송하면 응답을 수신합니다. `cs_n`이 High가 되면 진행 중인 프레임을 초기화하고 MISO를 High-Z로 해제합니다.

## Basys3 Slave 배선

| Basys3 핀 | Slave 포트 | 용도 |
| --- | --- | --- |
| JA1 | `sclk` | SPI 클록 |
| JA2 | `cs_n` | Chip Select, Active-Low |
| JA3 | `mosi` | Master에서 Slave로 전송 |
| JA4 | `miso` | Slave에서 Master로 전송 |
| SW15 | `reset` | Active-High 리셋 |

제약 파일은 `slave/constraints/Basys3-Master_orginal.xdc`에 있습니다.
