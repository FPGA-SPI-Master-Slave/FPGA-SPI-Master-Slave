# Basys 3 SPI Master

## 구조 및 FSM

`master_top`의 `start` 입력은 Basys 3의 btnC, `reset` 입력은 btnD에 연결합니다. `button_debounce10ms`의 1클럭 펄스로 `master_controller`를 시작합니다. Slave 통신은 전용 `master_byte`의 SPI를 사용하고, OLED는 `oled_controller`와 `oled_i2c`의 독립된 I²C를 사용합니다. 두 통신은 동시에 동작하며 OLED 초기화나 표시 때문에 Slave 수신이 대기하지 않습니다. SPI 바이트 모듈은 100 MHz 클럭에서 50클럭마다 SCLK를 토글합니다. MOSI는 첫 상승 에지 전에 설정하고 이후 하강 에지에서 변경하며 MISO는 상승 에지에서 샘플링합니다.

```text
IDLE --버튼/CS Low--> STATUS_START -> STATUS_WAIT
  -> RESPONSE_START -> RESPONSE_WAIT --BUSY, 제한 미만--> STATUS_START
                                 |--READY--> SEND_START -> SEND_WAIT
                                 |             -> 거리 상위/하위/상태 수신
                                 |             -> 데이터 저장/CS High -> RESTART -> STATUS_START
                                 |--BUSY 제한 도달--> timeout/CS High -> IDLE
                                 `--알 수 없는 응답--> 오류/CS High -> IDLE
```

버튼을 한 번 누르면 데이터 수신 후 Slave CS를 해제하고 상태 확인부터 반복합니다. reset 또는 Slave 통신 오류가 발생하면 반복을 중단합니다. 각 START는 1클럭 요청이고 WAIT는 바이트 전송 종료를 기다립니다. 바이트 사이에 SCLK는 Low로 쉬지만 CS는 유지됩니다. 실행 중 버튼은 무시합니다. reset은 작업을 중단하며 CS를 해제하고 I²C 선을 해제합니다. LED[7:0]은 마지막으로 수신 완료한 거리 하위 바이트, LED[8]은 timeout, LED[9]는 알 수 없는 응답을 표시합니다. LED[9:8]의 오류 표시는 다음 시작 시 지워집니다. LED[10]은 OLED의 I²C NACK 또는 시간 초과를 표시하며 OLED 초기화가 성공하면 지워집니다. LED[11]은 최근 주소 단계의 ACK 응답, LED[12]는 화면 지우기와 화면 켜기를 포함한 초기화 완료를 표시합니다.

## OLED 표시 및 배선

SSD1306 128×64, GND/VCC/SCL/SDA 4핀 I²C 모듈을 기준으로 합니다. 전원 안정화 대기 후 화면을 끈 상태에서 OLED 초기화와 화면 지우기를 마친 뒤 화면을 켭니다. 아직 수신 값이나 통신 오류가 없으면 화면 왼쪽 위에 `READY`를 표시합니다. 슬레이브 연결이나 btnC 입력 없이 OLED 준비 완료를 확인할 수 있으며 reset 후에도 같은 순서로 표시합니다. 첫 정상 데이터 수신 시 최신 16비트 값을 단위 없이 5자리 십진수로 표시합니다. 초기화 중 이미 데이터나 오류가 들어왔다면 해당 숫자 또는 `ERROR`를 우선 표시합니다. 예를 들어 4773은 `04773`으로 표시합니다. 이후 기본 0.1초 간격으로 최신 값을 갱신합니다. 표시 도중 새 데이터가 들어와도 한 화면의 값은 고정하며 다음 갱신에 반영합니다. 상태 바이트는 화면에 사용하지 않습니다. `OLED_RESET_CYCLES`는 전원 안정화 및 OLED 재시도 대기 시간으로 100 MHz 기준 기본 100 ms입니다. 별도 OLED RESET 핀은 사용하지 않습니다. `OLED_REFRESH_CYCLES`는 기본 100 ms이며 두 값은 양수로 설정합니다.

BUSY timeout 또는 알 수 없는 응답이 발생하면 숫자 대신 `ERROR`를 표시합니다. 첫 정상 데이터를 받기 전 오류가 발생해도 표시하며, OLED 초기화나 진행 중인 거래가 끝나면 기본 갱신 주기를 기다리지 않고 화면을 갱신합니다. 재시작 버튼을 눌러도 새 정상 데이터의 3바이트 수신이 완료될 때까지 `ERROR`를 유지하며, 수신 성공 시 숫자 표시로 복구합니다. reset은 오류 기록을 지우고 OLED를 다시 초기화합니다. 수신한 상태 바이트의 의미는 정의되지 않아 오류 판단에 사용하지 않습니다.

| 신호 | Basys 3 연결 | 연결 대상 |
| --- | --- | --- |
| SCLK | JA1 | Slave SCLK |
| MOSI | JA2 | Slave MOSI |
| MISO | JA3 | Slave MISO |
| Slave CS | JA4 | Slave CS |
| OLED SCL (`sclk`) | JB1, FPGA A14 | OLED SCL |
| OLED SDA (`sda`) | JB2, FPGA A16 | OLED SDA |
| OLED GND | JB5 | OLED GND |
| OLED VCC | JB6, 3.3 V | OLED VCC, 3.3 V 지원 확인 |

두 장치와 Basys 3의 GND를 공통으로 연결합니다. SCL/SDA는 0 또는 하이 임피던스로 구동하는 오픈 드레인입니다. 두 선 모두 3.3 V 풀업 저항이 필요하며, 모듈에 내장되지 않았다면 각 선과 3.3 V 사이에 4.7 kΩ 저항을 추가합니다. 5 V로 풀업하지 마세요. OLED 모듈의 전원 및 3.3 V 로직 호환성, 핀 순서와 해상도는 실제 모듈 사양에 맞춰 확인해야 합니다. JA7/8/9의 기존 OLED CS/D/C/RESET 배선은 사용하지 않습니다.

`OLED_I2C_ADDRESS`는 7비트 주소이며 기본 `7'h3c`입니다. 기본 `OLED_I2C_AUTO_ADDRESS=1`에서는 주소 단계가 NACK일 때 `0x3C`와 `0x3D`를 번갈아 확인하며 ACK를 받으면 그 주소를 유지합니다. 제어 바이트나 화면 내용의 NACK에서는 주소를 바꾸지 않습니다. 주소를 고정하려면 `OLED_I2C_AUTO_ADDRESS=0`으로 설정하고 `OLED_I2C_ADDRESS`를 지정합니다. `0x78`처럼 쓰기 비트를 포함한 8비트 값을 넣지 마세요. `OLED_I2C_QUARTER_PERIOD` 기본 250에서 SCL은 약 100 kHz이며 외부 클럭 지연에 따라 느려질 수 있습니다. 각 화면 바이트는 `START → 주소+W → ACK → 제어 바이트(명령 00/화면 데이터 40) → ACK → 내용 → ACK → STOP`으로 전송합니다. 모든 ACK를 확인하며 NACK 발생 시 STOP 후 초기화부터 재시도합니다. `OLED_I2C_TIMEOUT_CYCLES`는 한 거래의 제한으로 기본 10 ms이며 SCL 또는 SDA가 계속 낮아도 선을 해제하고 재시도합니다. 이 오류는 LED[10]에 표시하며 Slave SPI에는 영향을 주지 않습니다. OLED 자체가 응답하지 않는 동안에는 화면의 `ERROR` 표시를 보장할 수 없습니다.

I²C 전송 형식은 [SSD1306 데이터시트 8.1.5절](https://cdn-shop.adafruit.com/datasheets/SSD1306.pdf), 오픈 드레인과 타이밍은 [NXP I²C 규격](https://www.nxp.com/docs/en/user-guide/UM10204.pdf)을 기준으로 합니다.

OLED 바이트 생성에는 나눗셈과 나머지 연산을 사용하지 않습니다. 페이지·열·문자 위치는 별도 카운터로 진행하고, 16비트 숫자는 16클럭 동안 십진수로 변환합니다. 계산된 바이트와 명령 구분 값을 레지스터에 저장한 다음 I²C 전송을 요청하므로 한 클럭에 긴 조합연산이 연결되지 않습니다. 이 변환 중 들어온 새 센서 값은 다음 화면 갱신에 반영합니다.

## 임시 프로토콜 (Slave 담당자와 합의 필요)

MSB first, Mode 0. 명령 바이트를 전송할 때의 MISO는 무시하고, 바로 다음 더미 바이트 `00`을 전송하는 8클럭에서 응답을 받습니다. STATUS `10`의 응답은 BUSY `00` 또는 READY `01`입니다. READY 뒤 SEND `20`을 보내고 더미 바이트 3개를 전송하면서 거리 상위, 거리 하위, 상태 바이트를 순서대로 받습니다. 세 바이트가 모두 수신되면 함께 갱신하며 거리는 `{distance_high, distance_low}`입니다. 상태 바이트는 그대로 저장하며 의미는 아직 정의되지 않았습니다. 명령값과 응답값은 제공된 표를 따릅니다. 3바이트 형식, 응답 시작 시점, 바이트 사이 SCLK 정지 허용, CS 유지, 전기 및 시간 조건은 Slave 담당자와 합의해야 합니다. 파라미터 `MAX_POLLS`(기본 1000)는 허용되는 BUSY 응답 수이며 마지막 BUSY에서 timeout합니다. 기본 1 MHz에서 약 16 ms이며 바이트 사이의 시스템 클럭 지연이 추가됩니다. 각 파라미터는 양수여야 합니다.

## Vivado 사용

Git에서 관리하는 설계 소스는 `src`, 핀 제약은 `constraints`, 테스트벤치는 `sim`에 있습니다. Vivado에서 새 프로젝트를 만들 때 `src`의 `button_debounce10ms.v`, `master_byte.v`, `master_controller.v`, `oled_controller.v`, `oled_i2c.v`, `master_top.v`를 설계 소스로, `constraints/Basys3-Master_orginal.xdc`를 제약 파일로, `sim/tb_master.v`와 `sim/tb_oled_i2c.v`를 시뮬레이션 소스로 추가합니다. 설계 top은 `master_top`, 통합 시뮬레이션 top은 `tb_master`, I²C 전송기 검사 top은 `tb_oled_i2c`입니다.

`sim/tb_oled_controller.v`를 추가하면 top `tb_oled_controller`로 0·65535 및 십진 자리 경계를 포함한 45개 숫자, 변환 중 새 데이터 수신, `READY`·`ERROR`·정상 복구를 검사할 수 있습니다.

현재 작업 프로젝트는 `spi_master/spi_master.xpr`이며 실제 등록 소스는 `spi_master/spi_master.srcs/sources_1/new`, 제약은 그 아래 `constrs_1/imports/digilent-xdc-master`, 테스트벤치는 `sim_1/new`를 사용합니다. 프로젝트 내부 파일을 기준으로 수정하고 Git 관리용 `src`, `constraints`, `sim`에도 같은 내용을 반영합니다. 동일 모듈의 두 복사본을 함께 등록하지 마세요. `spi_master` 폴더와 `.xpr`은 Git에서 제외됩니다.

통합 시뮬레이션은 실제 I²C 선에서 주소, 제어 바이트, 초기화 25바이트와 화면 지우기 전체 및 마지막 화면 켜기 명령, `READY`, 숫자와 `ERROR`의 글꼴 데이터를 복호화해 검사합니다. 전원 인가 및 reset 후 슬레이브 통신 없이 `READY`가 출력되는지도 검사합니다. 버튼 한 번으로 거리 `12A5`, `12A6` 및 상태 `5A` 연속 수신, SPI와 I²C의 동시 동작, reset, BUSY timeout, 미정의 응답, 정상 복구, 첫 수신 전 오류, OLED NACK 및 재연결도 검사합니다. 실행 시간을 줄이기 위해 디바운스와 전원 대기를 4클럭, I²C 분주를 5로 줄이며 SPI SCLK는 실제 1 MHz로 유지합니다. `tb_oled_i2c`는 기본 약 100 kHz에서 SCL high/low 시간, 주소 0x3C/0x3D 자동 확인과 각 주소의 통합 출력, 모든 바이트 위치의 NACK, 클럭 지연, SCL/SDA 고정 시 시간 초과, 전송 중 reset을 별도로 검사합니다. 실제 하드웨어의 외부 장치 입출력 타이밍은 Slave와 OLED의 사양 및 배선에 맞춰 별도로 검증해야 합니다.

2026-11-05 기본 파라미터와 현재 XDC로 Vivado 2020.2 합성·배치배선을 검증했습니다. 100 MHz 내부 타이밍의 WNS는 +1.250 ns, WHS는 +0.131 ns이며 setup/hold 실패와 DRC 위반은 0건입니다. 프로젝트 비트스트림은 `spi_master/spi_master.runs/impl_1/master_top.bit`, 보고서는 `spi_master/oled_recovery_build/timing_summary.rpt`와 `spi_master/oled_recovery_build/drc.rpt`에 있습니다. `output` 폴더에도 동일 생성물 사본을 보관합니다. 생성물은 Git 관리 대상이 아니며 소스나 핀 변경 후 다시 생성해야 합니다. 외부 입출력 지연 제약은 아직 추가하지 않았으므로 이 결과가 장치와 배선의 외부 타이밍 검증을 대신하지는 않습니다.
