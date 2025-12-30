

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

## Target: PIC16F877A
This project targets the PIC16F877A microcontroller. Assembly sources in this repository are written for mid-range PIC architecture and assume standard configuration bits (oscillator, watchdog, etc.). Adjust configuration bits and oscillator frequency to match your hardware.

## PicSimLab — Hızlı Simülasyon
1. Açın PicSimLab.
2. `File -> Open` ile istediğiniz `.asm` dosyasını yükleyin (ör. `board2.asm`).
3. Device/Chip seçiminden `PIC16F877A`'yı seçin.
4. Oscillator frekansını ve konfigürasyon bitlerini ayarlayın (ör. 4MHz veya 8MHz; WDT, MCLR seçenekleri).
5. Simülasyonu başlatın (Assemble / Run). UART kullanıyorsa PicSimLab içindeki terminal penceresini etkinleştirip seri çıktıyı izleyin.

Not: PicSimLab, giriş/çıkış pinlerini ve çevresel periferi birimleri simüle eder; gerçek donanım programlama adımlarına geçmeden önce algoritmanızı doğrulamak için uygundur.

## MPLAB X IDE — Proje Oluşturma ve Programlama
GUI adımları:
1. MPLAB X'i açın ve `File -> New Project` seçin.
2. Category: `Microchip Embedded`, Project: `Standalone Project` seçin.
3. Device olarak `PIC16F877A`'yı seçin.
4. Tool olarak programlayıcınızı seçin (ör. PICkit3, PICkit4, ICD 3/4).
5. Compiler olarak `XC8` (C için) veya assembler desteği için uygun toolchain'i seçin. Assembly dosyaları için genellikle XC8 paketindeki assembler veya MPASM kullanılabilir—projeye `.asm` dosyalarını ekleyin.
6. `Source Files` altına mevcut `.asm` dosyalarını (`board2.asm`, `with_uart_v2.asm`, vb.) ekleyin.
7. `Build` ile derleyin. Hata/uyarıları kontrol edin ve konfigürasyon bitlerini (Configuration Bits) projenizde doğru ayarlayın.
8. Hedef donanıma programlamak için `Run -> Program Device` (veya ilgili programlama komutunu) kullanın.

CLI/Notlar:
- Eğer MPLAB X komut satırı araçlarını kullanmak isterseniz, proje için oluşturulan `makefile` ile `make` komutunu kullanabilirsiniz (MPLAB X'in platform-tools ve komut satırı ortamının kurulu olması gerekir).
- Programlayıcı: PICkit3/4 veya ICD kullanıyorsanız cihazın sürücülerinin yüklü olduğundan emin olun.

## Prerequisites
- Python 3.8+ to run the UI scripts (`Board1_UI.py`, `board2ui.py`, `main.py`).
- PicSimLab (for quick assembly simulation).
- MPLAB X IDE and a Microchip programmer (PICkit3/4 or ICD) to build and program the target.

## Quick start
1. Simülasyon: PicSimLab ile hızlı doğrulama yapın (bkz. PicSimLab bölüm).
2. Gerçek donanım: MPLAB X'te yeni bir proje oluşturup `.asm` dosyalarını ekleyin, derleyin ve programlayıcı ile cihaza yazın.

## Notes
- Eğer spesifik konfigürasyon bitleri, osilatör frekansı veya kullandığınız programlayıcı hakkında bilgi verirseniz, README'ye adım adım örnek komutlar ve `Configuration Bits` ayarları ekleyebilirim.

## Contributing
- Improvements, bugfixes, and clearer usage instructions are welcome. Open issues or send a pull request with changes.

## License
- This project does not include a license file. If you want an open-source license, tell me which one and I will add it.

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



