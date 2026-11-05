# Basys 3 SPI Master

## 구조 및 FSM

`master_top`의 `start` 입력은 Basys 3의 btnC, `reset` 입력은 btnD에 연결합니다. `master_top`은 버튼과 LED를 연결하며 `button_debounce10ms`의 1클럭 펄스로 `master_controller`를 시작합니다. 컨트롤러는 `master_byte`에 전송 바이트와 시작 펄스를 전달하고 완료 및 수신 바이트를 받습니다. 바이트 모듈은 100 MHz 클럭에서 50클럭마다 SCLK를 토글합니다. MOSI는 첫 상승 에지 전에 설정하고 이후 하강 에지에서 변경하며 MISO는 상승 에지에서 샘플링합니다.

```text
IDLE --버튼/CS Low--> STATUS_START -> STATUS_WAIT
  -> RESPONSE_START -> RESPONSE_WAIT --BUSY, 제한 미만--> STATUS_START
                                 |--READY--> SEND_START -> SEND_WAIT
                                 |             -> 거리 상위/하위/상태 수신
                                 |             -> 데이터 저장/CS High -> RESTART -> STATUS_START
                                 |--BUSY 제한 도달--> timeout/CS High -> IDLE
                                 `--알 수 없는 응답--> 오류/CS High -> IDLE
```

버튼을 한 번 누르면 데이터 수신 후 CS를 한 클록 동안 해제하고 상태 확인부터 반복합니다. reset 또는 통신 오류가 발생하면 반복을 중단합니다. 각 START는 1클럭 요청이고 WAIT는 바이트 전송 종료를 기다립니다. 바이트 사이에 SCLK는 Low로 쉬지만 CS는 유지됩니다. 실행 중 버튼은 무시합니다. reset은 작업을 중단하며 CS를 해제합니다. LED[7:0]은 마지막으로 수신 완료한 거리 하위 바이트, LED[8]은 timeout, LED[9]는 알 수 없는 응답을 표시합니다. 오류 표시들은 다음 시작 시 지워집니다.

## 임시 프로토콜 (Slave 담당자와 합의 필요)

MSB first, Mode 0. 명령 바이트를 전송할 때의 MISO는 무시하고, 바로 다음 더미 바이트 `00`을 전송하는 8클럭에서 응답을 받습니다. STATUS `10`의 응답은 BUSY `00` 또는 READY `01`입니다. READY 뒤 SEND `20`을 보내고 더미 바이트 3개를 전송하면서 거리 상위, 거리 하위, 상태 바이트를 순서대로 받습니다. 세 바이트가 모두 수신되면 함께 갱신하며 거리는 `{distance_high, distance_low}`입니다. 상태 바이트는 그대로 저장하며 의미는 아직 정의되지 않았습니다. 명령값과 응답값은 제공된 표를 따릅니다. 3바이트 형식, 응답 시작 시점, 바이트 사이 SCLK 정지 허용, CS 유지, 전기 및 시간 조건은 Slave 담당자와 합의해야 합니다. 파라미터 `MAX_POLLS`(기본 1000)는 허용되는 BUSY 응답 수이며 마지막 BUSY에서 timeout합니다. 기본 1 MHz에서 약 16 ms이며 바이트 사이의 시스템 클럭 지연이 추가됩니다. 각 파라미터는 양수여야 합니다.

## Vivado 사용

Git에서 관리하는 설계 소스는 `src`, 핀 제약은 `constraints`, 테스트벤치는 `sim`에 있습니다. Vivado에서 새 프로젝트를 만들 때 `src`의 `button_debounce10ms.v`, `master_byte.v`, `master_controller.v`, `master_top.v`를 설계 소스로, `constraints/Basys3-Master_orginal.xdc`를 제약 파일로, `sim/tb_master.v`를 시뮬레이션 소스로 추가합니다. 설계 top은 `master_top`, 시뮬레이션 top은 `tb_master`입니다.

기존 로컬 Vivado 프로젝트는 `spi_master/spi_master.srcs`의 복사본을 참조할 수 있습니다. 이 폴더는 Git에서 제외하므로, 기존 프로젝트에서도 위 Git 관리 파일을 직접 참조하도록 소스 등록을 바꿔야 변경 사항이 일치합니다. 동일 모듈의 두 복사본을 함께 등록하지 마세요. `.xpr`도 Git에서 제외됩니다. JA1=SCLK, JA2=MOSI, JA3=MISO, JA4=CS_n, 공통 GND 및 3.3 V I/O입니다. 보드와 연결 장치의 전압 및 신호 연결을 확인하세요.

시뮬레이션은 버튼 한 번으로 거리 `12A5`, `12A6` 및 상태 `5A` 연속 수신, reset으로 중단, BUSY timeout, 미정의 응답, 각 바이트 내 1 MHz SCLK의 high/low 시간을 검사합니다. 테스트벤치는 디바운스 시간을 줄여 실행하며 SCLK는 실제 1 MHz로 유지합니다. 실제 하드웨어의 외부 장치 입출력 타이밍은 Slave의 데이터시트 및 배선에 맞춰 별도로 검증해야 합니다.
