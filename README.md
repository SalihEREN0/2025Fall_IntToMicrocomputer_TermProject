# Microcomputer Project — Fall 2025

## Authors
**Buğra Ayrancı** — Computer Engineering  
**Salih Eren** — Computer Engineering  
**Boran Yıldırım** — Electrical & Electronics Engineering  
**Alper Enes Gündüz** — Electrical & Electronics Engineering  

---

## Project Overview

This project implements a distributed Home Automation System using **PIC16F877A** microcontrollers. The system is designed to be simulated and controlled via a PC interface. It consists of two distinct subsystems (boards) that communicate independently via UART with a central Python-based Desktop Application.

1.  **Board 1: Air Conditioner System:** Handles temperature monitoring, fan speed detection, and heater/cooler control logic using a PID-like feedback loop.
2.  **Board 2: Curtain & Light Control System:** Manages automated curtain deployment via stepper motors and monitors ambient light levels using LDRs.

---

## Tools & Technologies

The project is built and simulated using the following stack:

* **IDE & Compiler:** [MPLAB X IDE](https://www.microchip.com/en-us/tools-resources/develop/mplab-x-ide) with **PIC-AS** (XC8 Toolchain Assembler).
* **Simulation:** [PicSimLab](https://lcgamboa.github.io/picsimlab/) (Board 2 configuration provided as `.pcf`).
* **UART Emulation:** [com0com](https://com0com.sourceforge.net/) (Null Modem Emulator) for creating virtual serial port pairs to link PicSimLab with the Python script.
* **GUI Application:** Python 3 (`tkinter`, `pyserial`).

---

## System Architecture

### Board 1: Air Conditioner System
* [cite_start]**Firmware:** `with_uart_v2.asm` [cite: 296]
* **Microcontroller:** PIC16F877A (4MHz External Oscillator)
* **Key Logic:**
    * [cite_start]**TMR0:** Configured as a counter for Fan RPS (Revolutions Per Second) calculation. [cite: 349]
    * [cite_start]**ISR (Interrupt Service Routine):** Handles UART Data Reception (`RCIF`) and Keypad "A" button interrupts (`RB0/INTF`). [cite: 314]
    * [cite_start]**Multiplexing:** Drives a 4-digit 7-segment display using a frame-based refresh routine. [cite: 400]

### Board 2: Curtain & Light Control
* [cite_start]**Firmware:** `board2.asm` [cite: 428]
* **Microcontroller:** PIC16F877A
* **Key Logic:**
    * [cite_start]**ADC:** Multiplexed reading of Channel 0 (LDR) and Channel 1 (Potentiometer). [cite: 452]
    * [cite_start]**Stepper Driver:** Software-defined Half-Step or Full-Step sequence lookup table. [cite: 451]
    * [cite_start]**Modes:** Auto (Sensor-based) vs. Manual (Potentiometer/UART). [cite: 433]

---

## Hardware Pinout Configuration

### Board 1: Air Conditioner System
| Port/Pin | Function | Description |
| :--- | :--- | :--- |
| **RA0** | Analog Input | LM35 Temperature Sensor |
| **RA4** | Digital Input | Tachometer / Fan Speed Pulse (T0CKI) |
| **RB0 - RB3** | Input | Keypad Rows (Row 1 - Row 4) |
| **RB4 - RB7** | Output | Keypad Columns (Col 1 - Col 4) |
| **RC0 - RC3** | Output | 7-Segment Digit Select (Tens, Ones, Tenths, Hundredths) |
| **RC4** | Output | Heater Relay Control |
| **RC5** | Output | Cooler Relay Control |
| **RC6** | Output | UART TX (Transmit) |
| **RC7** | Input | UART RX (Receive) |
| **RD0 - RD7** | Output | 7-Segment Segments (a-g, dp) |

### Board 2: Curtain & Light Control System
| Port/Pin | Function | Description |
| :--- | :--- | :--- |
| **RA0** | Analog Input | LDR Light Sensor (ADC Channel 0) |
| **RA1** | Analog Input | Potentiometer (ADC Channel 1, Manual Control) |
| **RB0 - RB3** | Output | Stepper Motor Coils (4-wire control) |
| **RC6** | Output | UART TX (Transmit) |
| **RC7** | Input | UART RX (Receive) |
| **RD0** | Output | LCD RW (Read/Write) |
| **RD2** | Output | LCD RS (Register Select) |
| **RD3** | Output | LCD E (Enable) |
| **RD4 - RD7** | Output | LCD Data Lines (4-bit Mode: D4-D7) |

---

## Technical Calculations & Formulas

### 1. ADC (Analog-to-Digital) Calculations

The system uses the 10-bit ADC module of the PIC16F877A. Below are the specific mathematical models used in the assembly firmware.

#### **Board 1: Temperature Sensor (LM35)**
[cite_start]The firmware implements a specific routine to convert the raw ADC value into a readable Celsius degree with floating-point precision. [cite: 363]

* **Sensor:** LM35 (10mV / °C)
* **Reference Voltage (Vref):** 5V (5000mV)
* **ADC Resolution:** 2^10 - 1 = 1023
* **Formula Derivation:**
    > Voltage = ADC * (5000mV / 1023)
    >
    > Temp (°C) = Voltage / 10mV = (ADC * 5000) / (1023 * 10) = **(ADC * 500) / 1023**

* **Assembly Implementation:**
    [cite_start]The code explicitly multiplies the ADC result by 500 (using `MULTIPLY_16x8`) and divides by 1023. [cite: 364]

#### **Board 2: Light Sensor (LDR) & Potentiometer**
[cite_start]Board 2 uses a simplified 8-bit reading approach for threshold comparison. [cite: 453]

* **Resolution:** The code reads `ADRESH` (ADC Result High Byte) directly, effectively using the 8 Most Significant Bits (MSB).
* **Range:** 0 - 255
* **Threshold:** The system checks if the LDR value exceeds `d'100'`. [cite_start]If LDR > 100, the system switches to Auto Mode. [cite: 434]

### 2. UART Baud Rate Calculation

Both boards are configured to communicate at **9600 Baud**. [cite_start]The Baud Rate Generator (BRG) values are calculated based on the 4MHz crystal oscillator frequency. [cite: 352]

* **Oscillator Frequency (Fosc):** 4 MHz
* **UART Mode:** High Speed (BRGH = 1)
* **Formula:**
    > Baud Rate = Fosc / (16 * (SPBRG + 1))

* **Calculation used in Code:**
    * Target Baud: 9600
    * SPBRG Value set in code: **25**
    * **Actual Baud:** 4,000,000 / (16 * (25 + 1)) = 4,000,000 / 416 ≈ **9615**
    * **Error Rate:** ~0.16% (Within acceptable tolerance).

---

## Software Application (GUI)

The control interface is built using **Python 3** and **Tkinter**. It serves as the master control unit, sending commands and visualizing sensor data received from the simulated boards.

* [cite_start]**Entry Point:** `main.py` [cite: 490]
* **Features:**
    * [cite_start]**Port Scanning:** Automated enumeration of available COM ports via `serial.tools.list_ports`. [cite: 515]
    * [cite_start]**Real-time Monitoring:** Polling loops fetch sensor data every 1000ms. [cite: 535]
    * [cite_start]**Dual-Board Support:** Separate classes (`AirConditionerSystemConnection`, `CurtainControlSystemConnection`) manage distinct protocols. [cite: 495, 502]

---

## Setup & Simulation Guide

### 1. Environment Setup
1.  **Virtual Serial Ports:**
    * Install **com0com**.
    * Create a pair of virtual ports (e.g., `COM1` <-> `COM2`).
    * *Note: The Python script will connect to one end (e.g., COM1), and PicSimLab will connect to the other (e.g., COM2).*

2.  **Python Dependencies:**
    ```bash
    pip install pyserial tk
    ```

### 2. Firmware Compilation
1.  Open **MPLAB X IDE**.
2.  Create a new project for **PIC16F877A**.
3.  Select **pic-as** as the compiler toolchain.
4.  Add `with_uart_v2.asm` (for Board 1) or `board2.asm` (for Board 2) to the project.
5.  Build the project to generate the `.hex` files.

### 3. Running the Simulation (PicSimLab)
1.  Open **PicSimLab**.
2.  **Board 2 Setup:**
    * [cite_start]Load the provided configuration file: `board2configuration.pcf`. [cite: 488]
    * Alternatively, manually load `board2.hex` into the microcontroller.
    * Right-click the **Spare Part (IO UART)** component and set the Port to the virtual COM port designated for simulation (e.g., `COM2`).
3.  **Board 1 Setup:**
    * Select the appropriate board type (typically PICGenios or Breadboard with PIC16F877A).
    * Load `with_uart_v2.hex`.
    * Configure the UART serial interface to the virtual COM port (e.g., `COM4` <-> `COM3` pair).

### 4. Running the Application
1.  Run the main script:
    ```bash
    python main.py
    ```
2.  In the GUI, select the COM port paired with the simulator (e.g., `COM1` if simulator is on `COM2`).
3.  Click **Connect** to establish communication.

---

## Communication Protocol

### Board 1 Protocol (AC System)
| Command (Hex) | Direction | Description |
| :--- | :--- | :--- |
| `0x01` | TX -> RX | [cite_start]Request Desired Temp Fraction [cite: 497] |
| `0x02` | TX -> RX | Request Desired Temp Integer |
| `0x05` | TX -> RX | [cite_start]Request Fan Speed (RPS) [cite: 498] |
| `0xC0 | Val` | RX -> TX | [cite_start]Set Desired Temp Integer (Bits 0-5 = Value) [cite: 501] |

### Board 2 Protocol (Curtain System)
| Command (Hex) | Direction | Description |
| :--- | :--- | :--- |
| `0x02` | TX -> RX | [cite_start]Request Curtain Position (%) [cite: 504] |
| `0x08` | TX -> RX | [cite_start]Request Light Intensity [cite: 506] |
| `0xC0 | Val` | RX -> TX | [cite_start]Set Curtain Target Position (Bits 0-5 = Value) [cite: 509] |