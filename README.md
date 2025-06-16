# Advanced Computer-Aided VLSI System Design 

This repository contains implementations and documentation for four advanced computer-aided VLSI system design homeworks from NTU's Graduate Institute of Electronics Engineering (Spring 2025).   
Each task explores a different concept in ASIC design, simulation, and backend flow.  
This repository uses FINFET 16nm process, and due to the confidentiality, I cannot upload the files after synthesised, so there are only TB, RTL code, some scripts, UPF files are uploaded.  

## Topics
- UPF(united Power Format) and low power design techniques
- clock domain crossing
- AXI Protocol
- BIST(Built-in-self-test)
- DFT insertion
- Automatic Place & Route in Advanced 16nm Process

## 📦 HW1: Run-Length Encoder with Low Power Design

- Implemented a simplified lossy Run-Length Encoder (RLE) for image data with low-power design constraints.  
- Encoded 64x64 RGB image data using a pixel-value threshold of 10.  
- **Applied UPF (Unified Power Format) for multiple power domains and power switches.**  
- **Integrated SRAM usage and verified functionality with RTL and gate-level simulations.**  

## 🔲 HW2: Local Binary Pattern with AXI4

- Designed a hardware accelerator for extracting Local Binary Patterns (LBP) from grayscale images via AXI4 interface.  
- **Operated on 128x128 pixel images with memory mapping for input/output through AXI.**   
- **Performed Clock Domain Crossing (CDC) between control and data domains.**   
- Emphasized modularity by separating bus controller from the LBP processor logic.  

## 🔐 HW3: Keccak Hash Function with DFT Integration

- Implemented Keccak[272, 128] hash function accelerator supporting multiple operation modes including:  
  - Hash A only  
  - Hash A and B independently  
  - **BIST (Built-in Self-Test) for XOR2 modules**  
- **All XOR operations used a uniquely identified `xor2.v` module for fault isolation.**  
- **Integrated at least one scan chain and verified with gate-level simulations.**  
- Included DFT considerations like BIST and scan with synthesis and performance analysis.  

## 🛠️ HW4: APR (Automatic Place and Route) Flow

- Performed full backend flow using Innovus including:  
  - Synthesis netlist with pads (`PDCDG_V`)  
  - P&R flow setup using mmmc.view  
  - Scan chain disabling/enabling via modified `.sdc` scripts  
- Ensured critical path correctness, IR drop < 8%, and post-layout verification.  
- Included gate-level simulation after pad insertion and post-layout verification.  
- Generated final GDS after merging SRAM and analyzed APR report and area.  

## Midterm Project: Single-Layer Convolution Engine with Quantization
- Multi-bits CDC & AXI protocol & low power design
- check out https://github.com/shihjimmy/Single-Layer-Convolution-Engine-with-Quantization
