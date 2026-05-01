# Digital System Design

## 프로젝트 개요

Digital System Design은 FPGA/Vivado 기반 RTL 설계 실습과 최종 Super Resolution 가속기 프로젝트를 준비하는 학습 저장소입니다. 현재 Lab07까지 코드가 정리되어 있으며, 이후 Final 프로젝트로 확장할 예정입니다.

## 주요 특징

- Lab 단위로 RTL, testbench, simulation artifact, 참고 문서 분리 관리
- MAC, adder tree, BRAM/URAM/LUTRAM, line buffer, PE 기반 convolution 구조 실습
- Vivado XSIM 기반 기능 검증 흐름 정리
- FPGA accelerator 설계를 위한 데이터패스와 메모리 구조 단계별 구현
- 최종 Super Resolution 가속기 설계를 위한 선행 RTL 블록 축적

## 진행 현황

| 항목 | 상태 | 내용 |
| --- | --- | --- |
| Lab01 | 완료 | Vivado 프로젝트, VIO/ILA, 기본 adder RTL |
| Lab02 | 완료 | MAC, fixed-point adder tree, pipelined adder tree |
| Lab03 | 완료 | BRAM 기반 MAC datapath |
| Lab04 | 완료 | URAM/LUTRAM 기반 GEMV 구조 |
| Lab05 | 완료 | PE 기반 1D convolution 구조 |
| Lab06 | 완료 | 2D convolution, multi-channel convolution 구조 |
| Lab07 | 완료 | controller FSM, BRAM 기반 top, 3x3 convolution 구조 |
| Final Project | 예정 | Super Resolution 가속기 프로젝트 |

## 상세 스펙

| 항목 | 내용 |
| --- | --- |
| 프로젝트 유형 | 수업 실습 정리 + Final 프로젝트 준비 |
| 과목 | Digital System Design |
| 주요 언어 | Verilog, SystemVerilog |
| 개발 환경 | Xilinx Vivado, XSIM |
| 주요 자원 | DSP macro, BRAM, URAM, LUTRAM |
| 핵심 연산 | MAC, adder tree, GEMV, 1D/2D convolution |
| 최종 목표 | Super Resolution FPGA accelerator |

## Lab 구성

| Lab | 주요 내용 | 핵심 파일 |
| --- | --- | --- |
| Lab01 | 기본 RTL과 Vivado debug flow | `rtl/adder.v`, `rtl/top.v` |
| Lab02 | DSP MAC과 adder tree | `rtl/MAC.v`, `rtl/Adder_tree_fixed_point.v`, `rtl/pipelined_adder_tree.v` |
| Lab03 | BRAM과 MAC 연결 | `rtl/simple_dual_port_bram.v`, `rtl/mac_with_bram.v` |
| Lab04 | URAM/LUTRAM 기반 GEMV | `rtl/simple_dual_port_uram.v`, `rtl/simple_line_lutram.v`, `rtl/uram_based_gemv.v`, `rtl/lutram_line_buffer_gemv.v` |
| Lab05 | PE 기반 convolution | `rtl/pu.v`, `rtl/prob1_sc_pe3.v`, `rtl/prob2_mc_pe9.v` |
| Lab06 | 2D 및 multi-channel convolution | `rtl/TOP_prac1.v`, `rtl/TOP_prac2.v`, `rtl/TOP_prac3.v` |
| Lab07 | controller FSM과 BRAM 기반 convolution top | `rtl/controller.v`, `rtl/top.v`, `rtl/TOP_prac1.v` |

## 검증 결과 요약

- Lab01부터 Lab07까지 단계별 RTL 실습 코드가 정리되어 있습니다.
- MAC, memory, line buffer, PE, convolution datapath, controller FSM을 Final 프로젝트의 building block으로 재사용할 수 있게 구성했습니다.
- 현재 저장소는 Final Project를 이어서 추가하는 작업 공간입니다.
