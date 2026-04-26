# Digital System Design Lecture

Digital System Design 수업을 들으며 매주 진행한 RTL 설계 실습, 시뮬레이션 코드, 참고 자료를 정리하는 저장소입니다.  
최종 목표는 Super Resolution 가속기 설계 프로젝트이며, 이 저장소는 그 전까지 필요한 FPGA/Vivado 사용법, 연산기 구조, 메모리 기반 데이터 처리, convolution 구조를 단계적으로 연습한 기록입니다.

## 프로젝트 개요

이 저장소는 학부 3학년 디지털시스템설계 과목의 주차별 실습 자료를 Lab 단위로 정리합니다.  
각 Lab은 `rtl`, `tb`, `docs`, `sim` 등의 하위 폴더로 구성되어 있으며, Verilog/SystemVerilog 기반 RTL 설계와 Vivado XSIM을 통한 기능 검증 흐름을 포함합니다.

실습의 흐름은 단순 조합회로와 Vivado 사용법에서 시작해 MAC, adder tree, BRAM, line buffer, processing element, 1D/2D convolution 구조로 이어집니다.

## 한눈에 보기

| 항목 | 내용 |
| --- | --- |
| 프로젝트 유형 | 수업 실습 정리 + 최종 프로젝트 준비 |
| 과목 | Digital System Design |
| 주제 | FPGA 기반 디지털 시스템 및 가속기 설계 |
| 주요 언어 | Verilog, SystemVerilog |
| 개발 환경 | Vivado, XSIM |
| 최종 목표 | Super Resolution 가속기 설계 |

## 핵심 성과

- Vivado 프로젝트 생성, RTL 작성, 시뮬레이션 흐름 정리
- 고정소수점 기반 MAC, adder tree, pipelined adder tree 설계
- BRAM 기반 데이터 저장 및 연산 모듈 연동 실습
- DSP macro, LUTRAM/URAM/BRAM 등 FPGA 메모리 및 연산 자원 활용 연습
- Processing Element(PE)를 활용한 1D convolution 구조 설계
- 2D convolution 연산을 위한 line buffer와 multi-channel 데이터 처리 구조 실습

## 기능

- 주차별 Lab 자료 정리
- RTL 설계 파일과 테스트벤치 분리 관리
- Vivado XSIM 기반 동작 검증
- 입력/가중치 텍스트 파일을 활용한 시뮬레이션 데이터 관리
- FPGA 가속기 설계를 위한 기본 연산 블록 축적
- Super Resolution 최종 프로젝트를 위한 사전 학습 코드 보관

## 기술 스택

| 구분 | 내용 |
| --- | --- |
| 언어 | Verilog, SystemVerilog |
| 설계 방식 | RTL Design |
| 검증 방식 | Testbench Simulation |
| 개발 도구 | Xilinx Vivado |
| 시뮬레이터 | Vivado XSIM |
| 대상 분야 | FPGA Accelerator, Digital System Design |

## 프로젝트 구조

```text
Lecture/
+-- Lab01/
|   +-- docs/
|   +-- ip_repo/
|   +-- rtl/
|   +-- Vivado/
+-- Lab02/
|   +-- docs/
|   +-- rtl/
|   +-- tb/
+-- Lab03/
|   +-- docs/
|   +-- rtl/
|   +-- sim/
|   +-- tb/
+-- Lab04/
|   +-- docs/
|   +-- sim/
|   +-- tb/
+-- Lab05/
|   +-- docs/
|   +-- rtl/
|   +-- sim/
|   +-- tb/
+-- Lab06/
|   +-- docs/
|   +-- rtl/
|   +-- sim/
|   +-- tb/
+-- LICENSE
+-- README.md
```

## 결과

- [`Lab01/rtl`](Lab01/rtl)에서 Vivado 기반 FPGA 설계 흐름과 기본 RTL 모듈을 정리
- [`Lab02/rtl`](Lab02/rtl)에서 MAC, adder tree, pipelined adder tree 구조를 구현
- [`Lab03/rtl`](Lab03/rtl)에서 BRAM과 MAC을 연동한 메모리 기반 연산 구조를 실습
- [`Lab04`](Lab04)에서 FPGA accelerator architecture와 메모리 자원 활용 방식을 학습
- [`Lab05/rtl`](Lab05/rtl)에서 PE 기반 1D convolution 구조를 구현
- [`Lab06/rtl`](Lab06/rtl)에서 2D convolution 및 multi-channel 처리 구조를 실습

현재 저장소는 수업 진행에 맞춰 계속 업데이트되는 작업 공간이며, 일부 Vivado 산출물과 시뮬레이션 결과 파일은 정리 과정에서 제외될 수 있습니다.

## 참고

- 각 Lab의 강의 자료는 해당 Lab의 `docs/` 폴더에 정리
- RTL 설계 파일은 주로 각 Lab의 `rtl/` 폴더에 정리
- 테스트벤치는 각 Lab의 `tb/` 폴더에 정리
