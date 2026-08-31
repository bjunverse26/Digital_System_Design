# Digital System Design

FPGA 기반 RTL 설계의 기초부터 메모리 구조, convolution datapath, controller FSM, 3-layer SRCNN 가속기 구현까지 연결한 한 학기 설계 기록입니다.

## Term Project: 3-Layer SRCNN FPGA Accelerator

150 × 150 Y-channel 이미지 3장을 처리하는 signed 16-bit Q8.8 SRCNN 가속기 3종을 AMD Kria KV260에 구현했습니다. 과제에서 Zynq PS, Vitis firmware, AXI/URAM, Python demo 환경이 제공되었고, 4인 팀은 동일한 interface를 따르는 SRCNN IP 3종과 RTL testbench를 설계했습니다.

| 항목 | 내용 |
| --- | --- |
| Target FPGA | AMD Kria KV260 / XCK26 |
| Tool | Vivado 2023.1, XSIM |
| Network | 3-layer SRCNN |
| Operation | 3 × 3 Conv2D, Bias, Zero Padding, ReLU |
| Data format | Signed 16-bit Q8.8 fixed point |
| Clock constraint | 100 MHz |
| Verification | C++ fixed-point reference와 RTL 결과의 bit-level 비교 |

### Architecture and responsibility

| 구현 | Channel configuration | Architecture | 핵심 구조 |
| --- | --- | --- | --- |
| Recursive 1-4-2-1 | `1 → 4 → 2 → 1` | Recursive | Shared datapath, 2-pixel horizontal parallelism |
| Recursive 1-8-8-1 | `1 → 8 → 8 → 1` | Recursive | Layer 2의 64-PE channel-wise parallelism |
| Streamline 1-8-4-1 | `1 → 8 → 4 → 1` | Streamline | Layer별 PE·line buffer, stage overlap |

팀장을 맡아 세 구현의 interface와 검증 흐름을 조율했으며, **1-8-8-1 Recursive 가속기**의 controller, sliding-window line buffer, PE, post-processing, dual-port BRAM, weight/bias ROM, top으로 구성된 RTL 7개 모듈과 testbench를 설계·검증했습니다.

1-8-8-1 구조에서는 MAC 연산이 집중되는 Layer 2의 8 × 8 channel 조합을 64개 PE에 병렬 매핑했습니다. Sliding-window line buffer, packed activation memory, feature-map lifetime을 고려한 buffer reuse, Q8.8 post-processing으로 데이터 공급·저장 경로를 구성했습니다.

### 1-8-8-1 design decisions

| 관찰한 문제 | 설계 판단 | 확인된 결과 |
| --- | --- | --- |
| 전체 MAC 연산의 약 80%가 Layer 2에 집중 | 연산 병렬도는 64개의 3 × 3 convolution PE로 유지 | 병목 layer의 8 × 8 channel 조합을 병렬 처리 |
| 가변 column-select MUX의 선택 논리가 LUT를 크게 사용 | Shift 기반 sliding-window line buffer로 변경 | 변경 전후 전체 설계 합성 기준 LUT 약 15% 감소 |
| Layer 1·2 feature map을 별도 저장하면 중간 메모리가 중복 | 마지막 사용 시점을 기준으로 동일 buffer를 in-place reuse | 저장 요구량 5.76 Mbit에서 2.88 Mbit로 50% 감소 |

LUT 감소율은 line buffer block만의 자원 변화가 아니라, line buffer 구조 변경 전후의 **전체 1-8-8-1 가속기 합성 결과**를 비교한 값입니다.

> 세 구현은 channel configuration과 연산량이 서로 다릅니다. 아래 수치는 동일 모델의 미세 최적화 비교가 아니라, 각 네트워크를 구현한 최종 하드웨어의 latency와 resource footprint입니다.

## Verification

- Layer 1, Layer 2, final output을 C++ fixed-point reference와 비교해 세 구현 모두 **zero mismatch**를 확인했습니다.
- Self-checking testbench에서 output address/count와 이미지별 completion 신호를 함께 검증했습니다.
- 세 구현 모두 XCK26 post-route에서 **100 MHz timing constraint**를 만족했습니다.
- 제공된 PS/Vitis 환경에 IP를 통합해 FPGA 동작과 SRCNN 적용 후 PSNR 향상을 확인했습니다.

### Latency

100 MHz에서 `i_start`부터 세 번째 이미지의 최종 완료까지 측정했습니다.

| 구현 | Latency | Execution time |
| --- | ---: | ---: |
| Recursive 1-4-2-1 | 275,459 cycles | 2.755 ms |
| Recursive 1-8-8-1 | 413,183 cycles | 4.132 ms |
| Streamline 1-8-4-1 | 70,297 cycles | 0.703 ms |

### Post-route resource and timing

| 구현 | CLB LUT | BRAM Tile | DSP | WNS |
| --- | ---: | ---: | ---: | ---: |
| Recursive 1-4-2-1 | 57,820 (49.37%) | 73 (50.69%) | 145 (11.62%) | +0.589 ns |
| Recursive 1-8-8-1 | 104,335 (89.08%) | 112 (77.78%) | 577 (46.23%) | +2.012 ns |
| Streamline 1-8-4-1 | 40,977 (34.99%) | 33 (22.92%) | 397 (31.81%) | +1.968 ns |

### FPGA demo

![Bicubic and SRCNN result comparison](./DSD26_Termproject/03_Demo_Environment/srcnn_result.png)

| Dataset | Y-channel PSNR improvement |
| --- | ---: |
| `test_51` | +6.03 dB |
| `test_89` | +3.38 dB |
| `test_64` | +3.10 dB |

## Design progression

| Lab | 주요 내용 |
| --- | --- |
| Lab01 | Vivado project, VIO/ILA, basic RTL |
| Lab02 | MAC, fixed-point adder tree, pipeline |
| Lab03 | BRAM-based MAC datapath |
| Lab04 | URAM/LUTRAM-based GEMV |
| Lab05 | PE-based 1D multi-channel convolution |
| Lab06 | Sliding-window line buffer와 2D convolution |
| Lab07 | Controller FSM과 memory-integrated convolution top |

```text
MAC / Adder Tree
        ↓
FPGA Memory / PE
        ↓
Multi-channel Convolution
        ↓
Controller FSM
        ↓
SRCNN Accelerator
```

## Repository navigation

| 구현 | RTL | Testbench | Simulation guide | Implementation reports |
| --- | --- | --- | --- | --- |
| Recursive 1-4-2-1 | [rtl](./DSD26_Termproject/04_SRCNN_42/rtl/) | [tb](./DSD26_Termproject/04_SRCNN_42/tb/) | [AUTOMATION.md](./DSD26_Termproject/04_SRCNN_42/scripts/AUTOMATION.md) | [impl_snapshot](./DSD26_Termproject/04_SRCNN_42/impl_snapshot/) |
| Recursive 1-8-8-1 | [rtl](./DSD26_Termproject/05_SRCNN_88/rtl/) | [tb](./DSD26_Termproject/05_SRCNN_88/tb/) | [AUTOMATION.md](./DSD26_Termproject/05_SRCNN_88/scripts/AUTOMATION.md) | [impl_snapshot](./DSD26_Termproject/05_SRCNN_88/impl_snapshot/) |
| Streamline 1-8-4-1 | [rtl](./DSD26_Termproject/06_SRCNN_84/rtl/) | [tb](./DSD26_Termproject/06_SRCNN_84/tb/) | [AUTOMATION.md](./DSD26_Termproject/06_SRCNN_84/scripts/AUTOMATION.md) | [impl_snapshot](./DSD26_Termproject/06_SRCNN_84/impl_snapshot/) |

```text
Digital_System_Design/
├── Lab01 ... Lab07/             # 주차별 RTL 실습
└── DSD26_Termproject/
    ├── 04_SRCNN_42/
    ├── 05_SRCNN_88/
    ├── 06_SRCNN_84/
    ├── 03_Demo_Environment/
    └── docs/
```

각 구현 폴더의 `rtl`, `tb`, `init`, `ref`, `scripts`, `impl_snapshot`에는 각각 RTL source, self-checking testbench, initialization data, reference output, batch simulation script, post-route report가 포함되어 있습니다.

## Functional simulation

Vivado 2023.1의 `xvlog`, `xelab`, `xsim`을 사용하는 non-project batch flow입니다. Testbench의 reference path는 기존 제출 환경인 `C:\DSD26_Termproject_Materials`를 기준으로 하므로, `DSD26_Termproject`의 내용을 해당 경로에 배치하거나 동일 경로로 연결한 뒤 실행합니다.

```powershell
cd C:\DSD26_Termproject_Materials
vivado -nolog -nojournal -notrace -mode batch -source .\05_SRCNN_88\scripts\run_tb.tcl
```

`04_SRCNN_42`와 `06_SRCNN_84`도 각 폴더의 동일한 script 구성으로 실행할 수 있습니다. `-tclargs --keep`을 추가하면 simulation working directory를 보존합니다.

`00_RTL_Skeleton`, `01_Reference_SW`, `02_Provided_Data`, PS/Vitis demo source와 수업 guide는 제공 자료이므로 저장소에서 제외했습니다. RTL functional simulation에 필요한 initialization/reference data와 post-route report는 각 구현 폴더에 보존했습니다.

## Documents

- [Final report](./DSD26_Termproject/docs/DSD26_team6_report.pdf)
- [Presentation](./DSD26_Termproject/docs/DSD26_team6_presentation.pdf)
- [Proposal](./DSD26_Termproject/docs/26DSD_team_6_proposal.pdf)

## License

This project is distributed under the [MIT License](LICENSE).
