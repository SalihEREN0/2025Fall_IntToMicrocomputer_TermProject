# Microcomputer Project — Fall 2025: Home Automation System

## 👥 Project Team
**152120221055** — Buğra Ayrancı (Computer Engineering)  
**152120231091** — Salih Eren (Computer Engineering)  
**151220182059** — Boran Yıldırım (Electrical & Electronics Engineering)  
**151220222094** — Alper Enes Gündüz (Electrical & Electronics Engineering)

---

## 🏠 Project Overview

This project implements a distributed **Home Automation System** using **PIC16F877A** microcontrollers. The system is designed to be simulated via **PicSimLab** and controlled via a centralized **Python Desktop Application** (GUI).

It consists of two distinct subsystems that communicate independently via UART:
1.  **Board 1: Air Conditioner System:** Handles temperature monitoring, fan speed detection (Tachometer), and heater/cooler control using a hysteresis logic.
2.  **Board 2: Curtain & Light Control System:** Manages automated curtain deployment via stepper motors and monitors ambient light levels using LDRs.

---

## 📂 Project Structure & File Descriptions

* **`API.py`**: The main Python application containing the GUI, API classes, and logic for both boards. (Entry point).
* **`board1.asm`**: Assembly firmware for the Air Conditioner System (PIC16F877A).
* **`board2.asm`**: Assembly firmware for the Curtain & Light Control System (PIC16F877A).
* **`Board1_UI.py`**: Standalone Unit Test interface for Board 1.
* **`board2ui.py`**: Standalone Unit Test interface for Board 2.
* **`report.pdf`**: Detailed project report and design documentation.

---

## 🛠 Tools & Technologies

* **Microcontroller:** PIC16F877A
* **IDE & Compiler:** MPLAB X IDE / PIC-AS (XC8 Toolchain Assembler)
* **Simulation:** PicSimLab (Board: PICGenios / Breadboard)
* **Communication:** UART (Serial) @ 9600 Baud
* **GUI Application:** Python 3 (`tkinter`, `pyserial`)
* **Virtual Serial:** com0com (Null Modem Emulator)

---

## ⚙️ Hardware Architecture & Pinout

### Board 1: Air Conditioner System
* **Firmware:** `board1.asm`
* **Key Features:** LM35 Sensor, Multiplexed 7-Segment Display, Keypad (Interrupt-driven).

| Component | PIC Pin | Port | Function |
| :--- | :--- | :--- | :--- |
| **LM35 Sensor** | RA0 | PORTA | Analog Temp Input (ADC Ch 0) |
| **Tachometer** | RA4 | PORTA | Fan Speed Pulse Input (T0CKI) |
| **Heater (Relay)**| RC4 | PORTC | Active High Output |
| **Cooler (Fan)** | RC5 | PORTC | Active High Output |
| **Keypad Rows** | RB0-RB3| PORTB | Inputs (RB0 triggers INT) |
| **Keypad Cols** | RB4-RB7| PORTB | Outputs |
| **7-Seg Digits** | RC0-RC3| PORTC | Digit Enable (Active Low/High based on driver) |
| **7-Seg Segments**| RD0-RD7| PORTD | Segments (a-g, dp) |
| **UART TX** | RC6 | PORTC | Serial Transmit |
| **UART RX** | RC7 | PORTC | Serial Receive |

### Board 2: Curtain & Light Control
* **Firmware:** `board2.asm`
* **Key Features:** LDR Light Sensor, Stepper Motor Driver, Potentiometer for Manual Control.

| Component | PIC Pin | Port | Function |
| :--- | :--- | :--- | :--- |
| **LDR Sensor** | RA0 | PORTA | Light Intensity (ADC Ch 0) |
| **Potentiometer** | RA1 | PORTA | Manual Control (ADC Ch 1) |
| **Stepper Motor** | RB0-RB3| PORTB | Coils (4-wire Unipolar Sequence) |
| **LCD RS** | RD2 | PORTD | Register Select |
| **LCD EN** | RD3 | PORTD | Enable |
| **LCD D4-D7** | RD4-RD7| PORTD | Data Lines (4-bit mode) |
| **UART TX** | RC6 | PORTC | Serial Transmit |
| **UART RX** | RC7 | PORTC | Serial Receive |

---

## 📡 Communication Protocol

Both boards communicate at **9600 Baud**. The PC application acts as the master.

### Board 1 Protocol (AC System)
The system uses byte-level commands to fetch split integer/fractional values.

| Command (Hex) | Direction | Description |
| :--- | :--- | :--- |
| `0x01` | TX -> RX | Request Desired Temp Fraction (Decimal part) |
| `0x02` | TX -> RX | Request Desired Temp Integer |
| `0x03` | TX -> RX | Request Ambient Temp Fraction (Decimal part) |
| `0x04` | TX -> RX | Request Ambient Temp Integer |
| `0x05` | TX -> RX | Request Fan Speed (RPS) |
| `0x80 | Val` | RX -> TX | **Set** Desired Temp Fraction (Bits 0-5 = Value). Mask: `10xxxxxx` |
| `0xC0 | Val` | RX -> TX | **Set** Desired Temp Integer (Bits 0-5 = Value). Mask: `11xxxxxx` |

### Board 2 Protocol (Curtain System)
Controls curtain percentage and reads light levels.

| Command (Hex) | Direction | Description |
| :--- | :--- | :--- |
| `0x02` | TX -> RX | Request Curtain Status (%) |
| `0x08` | TX -> RX | Request Light Intensity (Lux/Raw) |
| `0xC0 | Val` | RX -> TX | **Set** Curtain Position (Bits 0-5 = Target %). Mask: `11xxxxxx` |

> **Note on BMP180:** The Python application includes logic to display Outdoor Temperature and Pressure. Since the current `board2.asm` firmware manages LDR and Potentiometer, the Pressure/Temp values are currently simulated (static) in the API layer.

---

## 💻 Software Application (GUI)

The control interface is built using **Python 3** and **Tkinter**. It features an Object-Oriented API design:

* **`HomeAutomationSystemConnection`**: Abstract base class handling serial connections and timeouts.
* **`AirConditionerSystemConnection`**: Handles Board 1 logic (splitting floats into integers/fractions).
* **`CurtainControlSystemConnection`**: Handles Board 2 logic.

### How to Run
1.  **Setup Virtual Ports:** Use `com0com` to create pairs (e.g., `COM1<>COM2` and `COM3<>COM4`).
2.  **Setup Simulator:**
    * Open PicSimLab.
    * Load `board1.hex` on one board (connect UART to `COM2`).
    * Load `board2.hex` on another board (connect UART to `COM4`).
3.  **Run Application:**
    ```bash
    pip install pyserial tk
    python API.py
    ```
4.  **Connect:**
    * In the GUI, select **Air Conditioner** -> Connect to `COM1`.
    * Select **Curtain Control** -> Connect to `COM3`.

---

## 🧮 Technical Calculations

### 1. ADC (Analog-to-Digital)
* **Formula:** `Voltage = ADC * (5000mV / 1023)`
* **Board 1 (Temp):** The firmware multiplies ADC result by 500 and divides by 1023 to get °C.
* **Board 2 (Light):** Uses 8-bit MSB reading for threshold comparison (Night/Day mode).

### 2. Baud Rate
* **Oscillator:** 4 MHz
* **Target:** 9600 Baud
* **SPBRG Value:** `25` (High Speed BRGH=1)
* **Calculation:** `4,000,000 / (16 * (25 + 1)) = 9615` (~0.16% Error).