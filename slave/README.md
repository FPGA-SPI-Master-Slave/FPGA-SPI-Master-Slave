# FPGA SPI Master/Slave

Vivado 2020.2 / Basys3 기반 프로젝트입니다. 현재 `spi-slave` 브랜치는 HC-SR04 거리 측정 결과를 SPI와 UART로 출력

- 최상위 모듈: `slave_top` (`slave/src/slave_top.v`)
- 핀 제약: `slave/constraints/Basys3-Master_orginal.xdc`
- 시스템 클럭: 100 MHz / SPI SCLK 제약: 1 MHz

## 거리 측정

100 ms 주기로 측정을 시작하며, Trig는 10 µs, Echo 대기·측정 제한은 각각 30 ms입니다. Echo HIGH 시간(µs)을 58로 나누어 정수 거리(cm)를 계산하고, 2~400 cm를 정상으로 판정.

최신 측정값은 버퍼에서 CDC 요청·응답 핸드셰이크를 거쳐 SPI로 전달되며, 별도의 4건 FIFO를 통해 UART로도 출력

## SPI 통신

Mode 0, MSB 우선, 8비트 단위입니다. CS를 LOW로 유지한 상태에서 명령을 보내고, Dummy 바이트를 전송해 응답을 읽음

| 명령 | 값 | 응답 |
| --- | --- | --- |
| STATUS | `0x10` | 1바이트: 유효 스냅샷이 있으면 READY(`0x01`), 없으면 BUSY(`0x02`) |
| SEND | `0x20` | 3바이트: 거리 상위 8비트 → 하위 8비트 → 상태(하위 3비트) |

SEND 응답은 한 측정값으로 고정되며, 유효 스냅샷이 없으면 3바이트 모두 `0x00`입니다. CS가 HIGH이면 SPI 프레임은 초기화.

측정 상태: `0`=NO_DATA, `1`=OK, `2`=NO_ECHO, `3`=ECHO_TIMEOUT, `4`=RANGE_ERROR.

## UART 및 LED

- UART: 115200 bps, 8N1. 출력 예: `DIST=0123 cm, OK\r\n`
- `led[0]`: SPI 활동 표시. 마지막 활동 후 200 ms 동안 점멸을 유지
- `led[1]`: CS가 LOW인 동안 SCLK 변화가 100 ms 이상 없으면 점등
- 입력 안정화: `cs_n` 풀업, `echo` 풀다운을 적용
