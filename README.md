
# Microcomputer Project — Fall 2025

Course project implementing microcomputer assembly and simple UIs.

## Authors
- Buğra Ayrancı — Computer Engineering
- Salih Eren — Computer Engineering
- Boran Yıldırım — Electrical & Electronics Engineering
- Alper Enes Gündüz — Electrical & Electronics Engineering

## Overview
This repository contains assembly source files, simple Python UI scripts, and supporting project files used for the Microcomputer course (Fall 2025). The code includes example assembly programs and small desktop UIs to interact with or simulate board behaviour.

## Repository structure
- `board2.asm`, `test.asm`, `with_uart_v2.asm` — Assembly source files used in the project.
- `board2configuration.pcf` — Pin/board configuration file (FPGA/PLD related).
- `Board1_UI.py`, `board2ui.py` — Python UI utilities for demonstration or control.
- `main.py` — Project entry point (if applicable for local demos).

## Prerequisites
- Python 3.8+ to run the UI scripts (`Board1_UI.py`, `board2ui.py`, `main.py`).
- An assembler / toolchain suitable for your target microcontroller or FPGA to assemble and program the `.asm` files.

## Quick start
1. Inspect the assembly sources to understand the examples (open `board2.asm`, `with_uart_v2.asm`).
2. To run the Python UI (if intended for your setup):

```powershell
python main.py
```

Replace `main.py` with `Board1_UI.py` or `board2ui.py` as appropriate for the demo you want to run.

## Notes
- This README is intentionally minimal. If you tell me which board/toolchain you use (e.g., specific microcontroller, assembler, or FPGA tool), I can add exact build/flash instructions and example commands.

## Contributing
- Improvements, bugfixes, and clearer usage instructions are welcome. Open issues or send a pull request with changes.

## License
- This project does not include a license file. If you want an open-source license, tell me which one and I will add it.



