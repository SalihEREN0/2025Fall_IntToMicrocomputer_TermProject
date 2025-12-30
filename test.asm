; PIC16F877A Temperature Control with 7-Segment Display
; Adapted to circuit: Segments on PORTD, Digits on PORTB
; Target: 27 degrees Celsius
PROCESSOR 16F877A
#include <xc.inc>

; Configuration
CONFIG FOSC = HS
CONFIG WDTE = OFF
CONFIG PWRTE = ON
CONFIG BOREN = ON
CONFIG LVP = OFF
CONFIG CPD = OFF
CONFIG WRT = OFF
CONFIG CP = OFF

; Constants
;#define TARGET_TEMP 27 ; Removed, using variable now
#define HEATER_PIN 4    ; RC4
#define COOLER_PIN 5    ; RC5
#define HEATER_PORT PORTC
#define COOLER_PORT PORTC

; Variables
PSECT udata_bank0
TARGET_TEMP_INT: DS 1   ; Desired Temp Integer
TARGET_TEMP_FRAC: DS 1  ; Desired Temp Fraction
AMBIENT_TEMP: DS 1
FRAC_TEMP: DS 1
VAL_INT: DS 1
VAL_FRAC: DS 1
FAN_SPEED_STORE: DS 1
TEMP_HIGH: DS 1
TEMP_LOW: DS 1
DELAY_COUNT: DS 1
DELAY_COUNT2: DS 1
TENS_DIGIT: DS 1
ONES_DIGIT: DS 1
TENTHS_DIGIT: DS 1
HUNDREDTHS_DIGIT: DS 1
DISPLAY_COUNT: DS 1
FRAME_COUNT: DS 1
TEMP_CHECK_COUNT: DS 1
SHOW_DP: DS 1
INPUT_MODE: DS 1
KEY_VAL: DS 1
INPUT_DIGIT_1: DS 1
INPUT_DIGIT_2: DS 1
INPUT_FRAC: DS 1
INPUT_STATE: DS 1
HAS_DP: DS 1
; New Input Variables
INPUT_TENS: DS 1
INPUT_ONES: DS 1
INPUT_TENTHS: DS 1
INPUT_HUNDREDTHS: DS 1
IS_FRAC_MODE: DS 1
FRAC_INDEX: DS 1
LAST_KEY: DS 1

; Interrupt Context
W_TEMP: DS 1
STATUS_TEMP: DS 1
PCLATH_TEMP: DS 1

; Math Variables
RES_0: DS 1
RES_1: DS 1
RES_2: DS 1
MATH_A_L: DS 1
MATH_A_H: DS 1
MATH_COUNT: DS 1
MATH_TEMP: DS 1
DIVISOR_L: DS 1
DIVISOR_H: DS 1
REM_0: DS 1
REM_1: DS 1

; UART Variables
UART_DATA: DS 1

; Reset Vector
PSECT resetVec,class=CODE,delta=2
GOTO MAIN

; Interrupt Vector
PSECT intVec,class=CODE,delta=2,abs
ORG 0x0004
GOTO ISR

; Main Code
PSECT code

ISR:
    ; Context Save
    MOVWF W_TEMP
    SWAPF STATUS, W
    MOVWF STATUS_TEMP
    CLRF STATUS
    MOVF PCLATH, W
    MOVWF PCLATH_TEMP
    CLRF PCLATH

    ; Check External Interrupt (RB0)
    BANKSEL INTCON
    BTFSS INTCON, 1 ; INTF
    GOTO ISR_EXIT
    
    ; 'A' Pressed Logic
    ; We assume Row 1 (RC4) is Low and others High.
    ; 'A' connects RC4 to RB0.
    ; So if INTF is set, 'A' was pressed.
    
    BANKSEL INPUT_MODE
    BSF INPUT_MODE, 0
    
    BANKSEL INTCON
    BCF INTCON, 1 ; Clear INTF

ISR_EXIT:
    ; Context Restore
    MOVF PCLATH_TEMP, W
    MOVWF PCLATH
    SWAPF STATUS_TEMP, W
    MOVWF STATUS
    SWAPF W_TEMP, F
    SWAPF W_TEMP, W
    RETFIE

MAIN:
    ; Power-up Delay to ensure hardware stability
    CALL DELAY
    CALL DELAY
    CALL DELAY
    
    BANKSEL INTCON
    CLRF INTCON ; Disable all interrupts initially

    CALL INIT_SYSTEM

MAIN_LOOP:
    ; Check Input Mode
    BANKSEL INPUT_MODE
    BTFSC INPUT_MODE, 0
    CALL HANDLE_INPUT_MODE
    
    ; Check UART for incoming commands
    CALL CHECK_UART

    ; --- 1. Ambient Temperature (2 Seconds) ---
    CALL READ_TEMPERATURE
    CALL CONTROL_TEMP
    
    BANKSEL AMBIENT_TEMP
    MOVF AMBIENT_TEMP, W
    MOVWF VAL_INT
    MOVF FRAC_TEMP, W
    MOVWF VAL_FRAC
    CALL CONVERT_TO_DIGITS
    
    ; Display for ~2s (45 frames × 4 = 180 frames × ~11ms = ~2s at 4MHz)
    MOVLW 45
    CALL DISPLAY_N_FRAMES
    BANKSEL INPUT_MODE
    BTFSC INPUT_MODE, 0
    GOTO MAIN_LOOP ; Restart loop to handle input immediately
    
    MOVLW 45
    CALL DISPLAY_N_FRAMES
    BANKSEL INPUT_MODE
    BTFSC INPUT_MODE, 0
    GOTO MAIN_LOOP
    
    MOVLW 45
    CALL DISPLAY_N_FRAMES
    BANKSEL INPUT_MODE
    BTFSC INPUT_MODE, 0
    GOTO MAIN_LOOP
    
    MOVLW 45
    CALL DISPLAY_N_FRAMES
    BANKSEL INPUT_MODE
    BTFSC INPUT_MODE, 0
    GOTO MAIN_LOOP
    
    ; --- 2. Target Temperature (2 Seconds) ---
    BANKSEL TARGET_TEMP_INT
    MOVF TARGET_TEMP_INT, W
    MOVWF VAL_INT
    MOVF TARGET_TEMP_FRAC, W
    MOVWF VAL_FRAC
    CALL CONVERT_TO_DIGITS
    
    MOVLW 45
    CALL DISPLAY_N_FRAMES
    MOVLW 45
    CALL DISPLAY_N_FRAMES
    MOVLW 45
    CALL DISPLAY_N_FRAMES
    MOVLW 45
    CALL DISPLAY_N_FRAMES
    
    ; --- 3. Fan Speed (RPS) ---
    ; Set DP OFF (Logic: 0 = OFF, 1 = ON)
    BANKSEL SHOW_DP
    CLRF SHOW_DP
    
    ; Start Measurement (Clear TMR0)
    BANKSEL TMR0
    CLRF TMR0
    
    ; Measure for ~1s (90 frames × ~11ms = ~1s at 4MHz)
    MOVLW 45
    CALL DISPLAY_N_FRAMES
    MOVLW 45
    CALL DISPLAY_N_FRAMES
    
    ; Read TMR0 (Pulses in 1s)
    BANKSEL TMR0
    MOVF TMR0, W
    MOVWF MATH_TEMP
    
    ; RPS = Pulses / 2 (2 pulses per rev)
    BCF STATUS, 0
    RRF MATH_TEMP, F
    
    ; R2.1.1-5: Save fan speed to memory address
    MOVF MATH_TEMP, W
    BANKSEL FAN_SPEED_STORE
    MOVWF FAN_SPEED_STORE
    
    ; Convert to 4 Digits (Integer Format: 0123)
    CALL CONVERT_RPS_TO_DIGITS
    
    ; Display Result for ~2s
    MOVLW 45
    CALL DISPLAY_N_FRAMES
    MOVLW 45
    CALL DISPLAY_N_FRAMES
    MOVLW 45
    CALL DISPLAY_N_FRAMES
    MOVLW 45
    CALL DISPLAY_N_FRAMES
    
    ; Restore DP for Temp Display
    BANKSEL SHOW_DP
    MOVLW 1
    MOVWF SHOW_DP
    
    GOTO MAIN_LOOP

; Initialize System
INIT_SYSTEM:
    BANKSEL TRISA
    MOVLW 0xFF          ; PORTA as input for ADC
    MOVWF TRISA
    
    ; PORTB: RB0-RB3 Inputs (Keypad Rows), RB4-RB7 Outputs (Keypad Cols)
    MOVLW 0x0F
    MOVWF TRISB
    
    ; PORTC: RC0-RC3 Outputs (Digits), RC4-RC5 (Heater/Cooler)
    ; RC6 = TX (output), RC7 = RX (input)
    MOVLW 0x80          ; RC7 input (RX), others output
    MOVWF TRISC
    
    CLRF TRISD          ; PORTD as output for segments
    
    ; ADC Configuration
    MOVLW 0x8E
    MOVWF ADCON1
    
    ; Timer0 / Option Configuration
    ; T0CS=1 (Counter on RA4), PSA=1 (Prescaler to WDT -> TMR0 is 1:1)
    ; RBPU=0 (Enable Pull-ups), INTEDG=0 (Falling Edge for 'A' press)
    MOVLW 0x28 ; RBPU=0, INTEDG=0, T0CS=1, PSA=1 (Fixed: 0x08 was T0CS=0)
    MOVWF OPTION_REG
    
    BANKSEL PORTA
    CLRF PORTA
    CLRF PORTB          ; All Cols Low initially
    CLRF PORTC          ; Heater/Cooler/Digits OFF initially
    CLRF PORTD          ; All segments OFF initially
    CLRF AMBIENT_TEMP
    CLRF FAN_SPEED_STORE
    CLRF INPUT_MODE
    
    ; Initialize Target Temp to 27.0
    BANKSEL TARGET_TEMP_INT
    MOVLW 27
    MOVWF TARGET_TEMP_INT
    CLRF TARGET_TEMP_FRAC
    
    BANKSEL SHOW_DP
    MOVLW 1
    MOVWF SHOW_DP
    
    BANKSEL TEMP_CHECK_COUNT
    MOVLW 50
    MOVWF TEMP_CHECK_COUNT
    
    ; ADC on, channel 0, FOSC/32
    MOVLW 0x81
    MOVWF ADCON0
    
    ; UART Configuration (9600 baud @ 4MHz)
    ; SPBRG = (FOSC / (16 * Baud)) - 1 = (4000000 / (16 * 9600)) - 1 = 25
    BANKSEL SPBRG
    MOVLW 25
    MOVWF SPBRG
    
    ; TXSTA: TX Enable, BRGH=1 (High Speed), Async Mode
    BANKSEL TXSTA
    MOVLW 0x24          ; TXEN=1, BRGH=1, SYNC=0
    MOVWF TXSTA
    
    ; RCSTA: Serial Port Enable, Continuous Receive
    BANKSEL RCSTA
    MOVLW 0x90          ; SPEN=1, CREN=1
    MOVWF RCSTA
    
    ; Clear any pending data
    BANKSEL RCREG
    MOVF RCREG, W
    MOVF RCREG, W
    
    ; Setup Keypad Idle State (Detect 'A')
    ; 'A' is at Row 1 (RB0) and Col 4 (RB7)
    ; Drive Col 4 (RB7) Low, others High
    BANKSEL PORTB
    MOVLW 0xF0 ; Set RB4-RB7 High
    MOVWF PORTB
    BCF PORTB, 7 ; Set RB7 Low
    
    ; Enable Interrupts
    BANKSEL INTCON
    BSF INTCON, 4 ; INTE (RB0 External Interrupt)
    BSF INTCON, 7 ; GIE (Global Interrupt Enable)
    
    CALL DELAY
    
    ; Ensure all unused digits are OFF
    BANKSEL PORTC
    MOVLW 0x00 ; Clear RC0-RC3
    MOVWF PORTC
    
    RETURN

; Read Temperature from ADC
READ_TEMPERATURE:
    BANKSEL ADCON0
    MOVLW 0x81
    MOVWF ADCON0
    
    CALL SHORT_DELAY
    CALL SHORT_DELAY
    
    BSF ADCON0, 2
    
WAIT_ADC:
    BTFSC ADCON0, 2
    GOTO WAIT_ADC
    
    ; Get ADC Result
    BANKSEL ADRESL
    MOVF ADRESL, W
    BANKSEL MATH_A_L
    MOVWF MATH_A_L
    
    BANKSEL ADRESH
    MOVF ADRESH, W
    BANKSEL MATH_A_H
    MOVWF MATH_A_H
    
    ; --- Calculate ADC * 500 ---
    ; 500 = 256 + 244
    ; Part 1: ADC * 244
    MOVLW 244
    CALL MULTIPLY_16x8
    ; Result in RES_2:RES_1:RES_0
    
    ; Part 2: Add ADC * 256 (ADC << 8)
    ; ADC_L goes to RES_1, ADC_H goes to RES_2
    BANKSEL MATH_A_L
    MOVF MATH_A_L, W
    BANKSEL RES_1
    ADDWF RES_1, F
    BTFSC STATUS, 0
    INCF RES_2, F
    
    BANKSEL MATH_A_H
    MOVF MATH_A_H, W
    BANKSEL RES_2
    ADDWF RES_2, F
    
    ; --- Divide by 1023 ---
    ; Setup Divisor
    BANKSEL DIVISOR_L
    MOVLW 0xFF ; Low byte of 1023
    MOVWF DIVISOR_L
    MOVLW 0x03 ; High byte of 1023
    MOVWF DIVISOR_H
    
    CALL DIVIDE_24x16
    
    ; Quotient (Integer Temp) is in RES_0
    BANKSEL RES_0
    MOVF RES_0, W
    BANKSEL AMBIENT_TEMP
    MOVWF AMBIENT_TEMP
    
    ; --- Calculate Fraction ---
    ; Remainder is in REM_1:REM_0
    ; Fraction = (Remainder * 100) / 1023
    
    ; Move Remainder to MATH_A (for Multiply)
    BANKSEL REM_0
    MOVF REM_0, W
    BANKSEL MATH_A_L
    MOVWF MATH_A_L
    BANKSEL REM_1
    MOVF REM_1, W
    BANKSEL MATH_A_H
    MOVWF MATH_A_H
    
    ; Multiply by 100
    MOVLW 100
    CALL MULTIPLY_16x8
    ; Result in RES
    
    ; --- Rounding ---
    ; Add 511 (1023 / 2) to Dividend for rounding
    ; 511 = 0x01FF
    BANKSEL RES_0
    MOVLW 0xFF
    ADDWF RES_0, F
    BTFSC STATUS, 0
    CALL INC_RES_1
    
    MOVLW 0x01
    ADDWF RES_1, F
    BTFSC STATUS, 0
    INCF RES_2, F
    
    ; Divide by 1023
    BANKSEL DIVISOR_L
    MOVLW 0xFF
    MOVWF DIVISOR_L
    MOVLW 0x03
    MOVWF DIVISOR_H
    
    CALL DIVIDE_24x16
    
    ; Quotient is Fraction
    BANKSEL RES_0
    MOVF RES_0, W
    BANKSEL FRAC_TEMP
    MOVWF FRAC_TEMP
    
    RETURN

; Multiply 16x8 Routine
; Inputs: MATH_A_H:MATH_A_L (Multiplicand), W (Multiplier)
; Output: RES_2:RES_1:RES_0
MULTIPLY_16x8:
    BANKSEL MATH_COUNT
    MOVWF MATH_COUNT
    CLRF RES_0
    CLRF RES_1
    CLRF RES_2
    
    MOVLW 8
    MOVWF MATH_TEMP ; Loop counter
    
MULT_LOOP:
    ; Shift Result Left (RES << 1)
    BCF STATUS, 0
    RLF RES_0, F
    RLF RES_1, F
    RLF RES_2, F
    
    ; Check MSB of Multiplier
    BCF STATUS, 0
    RLF MATH_COUNT, F
    BTFSS STATUS, 0
    GOTO SKIP_ADD
    
    ; Add Multiplicand to RES
    MOVF MATH_A_L, W
    ADDWF RES_0, F
    BTFSC STATUS, 0
    CALL INC_RES_1
    
    MOVF MATH_A_H, W
    ADDWF RES_1, F
    BTFSC STATUS, 0
    INCF RES_2, F

SKIP_ADD:
    DECFSZ MATH_TEMP, F
    GOTO MULT_LOOP
    RETURN

INC_RES_1:
    INCF RES_1, F
    BTFSC STATUS, 2 ; If wrapped to 0
    INCF RES_2, F
    RETURN

; DIVIDE_24x16 Routine
; Dividend: RES_2:RES_1:RES_0
; Divisor: DIVISOR_H:DIVISOR_L
; Output: Quotient in RES, Remainder in REM_1:REM_0
DIVIDE_24x16:
    BANKSEL REM_0
    CLRF REM_0
    CLRF REM_1
    
    MOVLW 24
    MOVWF MATH_COUNT
    
DIV_LOOP:
    ; Shift Dividend Left into Remainder
    BCF STATUS, 0
    RLF RES_0, F
    RLF RES_1, F
    RLF RES_2, F
    RLF REM_0, F
    RLF REM_1, F
    
    ; Compare REM vs DIVISOR
    MOVF DIVISOR_H, W
    SUBWF REM_1, W
    BTFSS STATUS, 0 ; C=0 means REM_1 < DIV_H
    GOTO NEXT_BIT
    BTFSS STATUS, 2 ; Z=0 means REM_1 > DIV_H (and C=1)
    GOTO SUBTRACT
    ; If Z=1 (Equal), Check Low
    MOVF DIVISOR_L, W
    SUBWF REM_0, W
    BTFSS STATUS, 0 ; C=0 means REM_0 < DIV_L
    GOTO NEXT_BIT
    
SUBTRACT:
    ; Subtract Divisor from Remainder
    MOVF DIVISOR_L, W
    SUBWF REM_0, F
    BTFSS STATUS, 0
    DECF REM_1, F
    MOVF DIVISOR_H, W
    SUBWF REM_1, F
    
    BSF RES_0, 0
    
NEXT_BIT:
    DECFSZ MATH_COUNT, F
    GOTO DIV_LOOP
    RETURN

; Control Temperature (Heater/Cooler)
CONTROL_TEMP:
    BANKSEL AMBIENT_TEMP
    MOVF AMBIENT_TEMP, W
    BANKSEL TARGET_TEMP_INT
    SUBWF TARGET_TEMP_INT, W      ; W = TARGET - AMBIENT
    
    BTFSC STATUS, 2        ; Check Z flag (Equal)
    GOTO CHECK_FRACTION    ; Integers equal, check fraction
    
    BTFSS STATUS, 0        ; Check C flag (If C=0, Result is negative -> TARGET < AMBIENT)
    GOTO TOO_HOT           ; Integer > Target (Wait, if C=0, Target < Ambient)
    
    ; If here, TARGET > AMBIENT (Too Cold)
    GOTO TOO_COLD

CHECK_FRACTION:
    ; Integers are equal. Check Fraction.
    ; If FRAC_TEMP > TARGET_FRAC -> Actual > Target -> Too Hot
    BANKSEL FRAC_TEMP
    MOVF FRAC_TEMP, W
    BANKSEL TARGET_TEMP_FRAC
    SUBWF TARGET_TEMP_FRAC, W ; W = TARGET_FRAC - ACTUAL_FRAC
    
    BTFSC STATUS, 2        ; Equal
    GOTO TEMP_OK
    
    BTFSS STATUS, 0        ; C=0 -> Target < Actual
    GOTO TOO_HOT
    
    GOTO TOO_COLD

TOO_COLD:
    ; target > ambient -> heater ON, fan OFF (need to heat up)
    BANKSEL PORTC
    BSF PORTC, HEATER_PIN
    BCF PORTC, COOLER_PIN
    RETURN

TOO_HOT:
    ; target < ambient -> heater OFF, fan ON (need to cool down)
    BANKSEL PORTC
    BCF PORTC, HEATER_PIN
    BSF PORTC, COOLER_PIN
    RETURN

TEMP_OK:
    BANKSEL PORTC
    BCF PORTC, HEATER_PIN
    BCF PORTC, COOLER_PIN
    RETURN

; Convert Temperature to Digits
CONVERT_TO_DIGITS:
    ; 1. Convert Integer Part
    BANKSEL VAL_INT
    MOVF VAL_INT, W
    CALL GET_DIGITS
    MOVWF ONES_DIGIT
    ; TENS_DIGIT is set correctly.
    
    ; 2. Convert Fractional Part
    ; We need to save TENS_DIGIT because GET_DIGITS uses it.
    MOVF TENS_DIGIT, W
    MOVWF MATH_TEMP ; Save Integer Tens
    
    BANKSEL VAL_FRAC
    MOVF VAL_FRAC, W
    CALL GET_DIGITS
    MOVWF HUNDREDTHS_DIGIT
    MOVF TENS_DIGIT, W
    MOVWF TENTHS_DIGIT
    
    ; Restore Integer Tens
    MOVF MATH_TEMP, W
    MOVWF TENS_DIGIT
    
    RETURN

CONVERT_RPS_TO_DIGITS:
    ; Input: MATH_TEMP (RPS Value)
    ; Output: TENS_DIGIT=Thousands, ONES_DIGIT=Hundreds, TENTHS_DIGIT=Tens, HUNDREDTHS_DIGIT=Ones
    
    BANKSEL TENS_DIGIT
    CLRF TENS_DIGIT       ; Digit 1 (Thousands) - Always 0 for RPS < 1000
    CLRF ONES_DIGIT       ; Digit 2 (Hundreds)
    CLRF TENTHS_DIGIT     ; Digit 3 (Tens)
    CLRF HUNDREDTHS_DIGIT ; Digit 4 (Ones)
    
    ; Calculate Hundreds
RPS_HUND_LOOP:
    MOVLW 100
    SUBWF MATH_TEMP, W
    BTFSS STATUS, 0
    GOTO RPS_HUND_DONE
    MOVWF MATH_TEMP
    INCF ONES_DIGIT, F
    GOTO RPS_HUND_LOOP
RPS_HUND_DONE:

    ; Calculate Tens
RPS_TENS_LOOP:
    MOVLW 10
    SUBWF MATH_TEMP, W
    BTFSS STATUS, 0
    GOTO RPS_TENS_DONE
    MOVWF MATH_TEMP
    INCF TENTHS_DIGIT, F
    GOTO RPS_TENS_LOOP
RPS_TENS_DONE:

    ; Ones
    MOVF MATH_TEMP, W
    MOVWF HUNDREDTHS_DIGIT
    RETURN

; Handle Input Mode
HANDLE_INPUT_MODE:
    ; Disable Interrupts during input
    BANKSEL INTCON
    BCF INTCON, 7 ; GIE
    
    ; Turn OFF Heater and Cooler immediately
    BANKSEL PORTC
    BCF PORTC, 4 ; Heater OFF
    BCF PORTC, 5 ; Cooler OFF
    
    ; Initialize Input Variables
    BANKSEL INPUT_TENS
    CLRF INPUT_TENS
    CLRF INPUT_ONES
    CLRF INPUT_TENTHS
    CLRF INPUT_HUNDREDTHS
    CLRF IS_FRAC_MODE
    CLRF FRAC_INDEX
    
    MOVLW 255
    MOVWF LAST_KEY
    
INPUT_LOOP:
    ; 1. Display Current Input
    CALL DISPLAY_INPUT_BUFFER
    
    ; 2. Display one frame then scan keypad (fast response)
    CALL DISPLAY_ONE_FRAME
    
    ; 3. Scan Keypad immediately after display
    CALL SCAN_KEYPAD
    BANKSEL KEY_VAL
    MOVWF KEY_VAL
    
    ; 3. Edge Detection (Press Event)
    BANKSEL KEY_VAL
    MOVF KEY_VAL, W
    BANKSEL LAST_KEY
    XORWF LAST_KEY, W
    BTFSC STATUS, 2 ; Z=1 if Current == Last
    GOTO INPUT_LOOP_CONTINUE ; No Change
    
    ; State Changed
    BANKSEL KEY_VAL
    MOVF KEY_VAL, W
    BANKSEL LAST_KEY
    MOVWF LAST_KEY
    
    ; Check if Key Released (255)
    SUBLW 255
    BTFSC STATUS, 2
    GOTO INPUT_LOOP_CONTINUE
    
    ; New Key Pressed! Process it.
    CALL PROCESS_KEY
    
    ; Long debounce delay after key press
    CALL DELAY
    
    ; Wait for key release with multiple confirmations
    MOVLW 3
    MOVWF MATH_TEMP         ; Need 3 consecutive "released" readings
    
WAIT_KEY_RELEASE:
    ; Keep display visible while waiting
    CALL DISPLAY_INPUT_BUFFER
    CALL DISPLAY_ONE_FRAME
    CALL DISPLAY_ONE_FRAME
    CALL DISPLAY_ONE_FRAME
    
    CALL SCAN_KEYPAD
    SUBLW 255
    BTFSS STATUS, 2         ; Z=1 if key released (255)
    GOTO WAIT_KEY_RESET     ; Key still pressed, reset counter
    
    ; Key released, decrement confirmation counter
    BANKSEL MATH_TEMP
    DECFSZ MATH_TEMP, F
    GOTO WAIT_KEY_RELEASE   ; Need more confirmations
    GOTO WAIT_KEY_DONE      ; Confirmed release
    
WAIT_KEY_RESET:
    MOVLW 3
    MOVWF MATH_TEMP         ; Reset confirmation counter
    GOTO WAIT_KEY_RELEASE
    
WAIT_KEY_DONE:
    ; Extra debounce after confirmed release
    CALL DELAY
    
    ; Reset LAST_KEY to 255 (released state)
    BANKSEL LAST_KEY
    MOVLW 255
    MOVWF LAST_KEY
    
INPUT_LOOP_CONTINUE:
    ; Check if we should exit (handled in PROCESS_KEY via flag or return?)
    ; We'll use INPUT_MODE bit 0 to signal exit.
    BANKSEL INPUT_MODE
    BTFSS INPUT_MODE, 0
    GOTO EXIT_INPUT_MODE
    
    GOTO INPUT_LOOP

EXIT_INPUT_MODE:
    ; Restore Idle State for Keypad (Col 4 Low)
    BANKSEL PORTB
    MOVLW 0xF0
    MOVWF PORTB
    BCF PORTB, 7
    
    ; Clear Interrupt Flag and Enable
    BANKSEL INTCON
    BCF INTCON, 1
    BSF INTCON, 7 ; GIE
    RETURN

PROCESS_KEY:
    BANKSEL KEY_VAL
    MOVF KEY_VAL, W
    
    ; Check for '#' (Enter) -> 11
    SUBLW 11
    BTFSC STATUS, 2
    GOTO KEY_ENTER
    
    ; Check for '*' (DP) -> 10
    MOVF KEY_VAL, W
    SUBLW 10
    BTFSC STATUS, 2
    GOTO KEY_DP
    
    ; Check for 'A' -> 12 (Ignore)
    MOVF KEY_VAL, W
    SUBLW 12
    BTFSC STATUS, 2
    RETURN
    
    ; Number (0-9)
    GOTO KEY_NUMBER

KEY_NUMBER:
    BANKSEL IS_FRAC_MODE
    BTFSC IS_FRAC_MODE, 0
    GOTO KEY_NUM_FRAC
    
    ; Integer Mode: Shift Left
    ; TENS = ONES
    ; ONES = KEY
    BANKSEL INPUT_ONES
    MOVF INPUT_ONES, W
    BANKSEL INPUT_TENS
    MOVWF INPUT_TENS
    
    BANKSEL KEY_VAL
    MOVF KEY_VAL, W
    BANKSEL INPUT_ONES
    MOVWF INPUT_ONES
    RETURN

KEY_NUM_FRAC:
    ; Allow 2 fractional digits (XX.XX format)
    BANKSEL FRAC_INDEX
    MOVF FRAC_INDEX, W
    SUBLW 1
    BTFSS STATUS, 0         ; C=0 if FRAC_INDEX > 1
    RETURN                  ; Already entered 2 digits, ignore further input
    
    ; Check which digit we're entering
    BANKSEL FRAC_INDEX
    MOVF FRAC_INDEX, W
    BTFSS STATUS, 2         ; Z=1 if FRAC_INDEX == 0
    GOTO FRAC_DIGIT_2
    
    ; First fractional digit (tenths)
    BANKSEL KEY_VAL
    MOVF KEY_VAL, W
    BANKSEL INPUT_TENTHS
    MOVWF INPUT_TENTHS
    BANKSEL FRAC_INDEX
    INCF FRAC_INDEX, F
    RETURN
    
FRAC_DIGIT_2:
    ; Second fractional digit (hundredths)
    BANKSEL KEY_VAL
    MOVF KEY_VAL, W
    BANKSEL INPUT_HUNDREDTHS
    MOVWF INPUT_HUNDREDTHS
    BANKSEL FRAC_INDEX
    INCF FRAC_INDEX, F
    RETURN

KEY_DP:
    BANKSEL IS_FRAC_MODE
    BSF IS_FRAC_MODE, 0
    BANKSEL FRAC_INDEX
    CLRF FRAC_INDEX
    RETURN

KEY_ENTER:
    ; Calculate full value for range check
    ; TARGET_TEMP_INT = TENS*10 + ONES
    BANKSEL INPUT_TENS
    MOVF INPUT_TENS, W
    MOVWF MATH_A_L
    CLRF MATH_A_H
    MOVLW 10
    CALL MULTIPLY_16x8
    BANKSEL RES_0
    MOVF RES_0, W
    BANKSEL INPUT_ONES
    ADDWF INPUT_ONES, W
    MOVWF MATH_TEMP         ; MATH_TEMP = integer part
    
    ; R2.1.2-3: Range Check (10.0 <= value <= 50.0)
    ; Check if integer < 10
    MOVLW 10
    SUBWF MATH_TEMP, W      ; W = INT - 10
    BTFSS STATUS, 0         ; C=0 if INT < 10
    GOTO REJECT_VALUE       ; Reject if < 10
    
    ; Check if integer > 50
    MOVF MATH_TEMP, W
    SUBLW 50                ; W = 50 - INT
    BTFSS STATUS, 0         ; C=0 if INT > 50
    GOTO REJECT_VALUE       ; Reject if > 50
    
    ; Check boundary case: if INT == 50, fraction must be 0
    MOVF MATH_TEMP, W
    SUBLW 50
    BTFSS STATUS, 2         ; Z=1 if INT == 50
    GOTO ACCEPT_VALUE       ; INT < 50, accept
    
    ; INT == 50, check fraction
    BANKSEL INPUT_TENTHS
    MOVF INPUT_TENTHS, W
    BTFSS STATUS, 2         ; Z=1 if TENTHS == 0
    GOTO REJECT_VALUE       ; Reject 50.x where x > 0
    
ACCEPT_VALUE:
    ; Save integer part
    MOVF MATH_TEMP, W
    BANKSEL TARGET_TEMP_INT
    MOVWF TARGET_TEMP_INT
    
    ; 2 fractional digits: TARGET_TEMP_FRAC = TENTHS * 10 + HUNDREDTHS
    BANKSEL INPUT_TENTHS
    MOVF INPUT_TENTHS, W
    MOVWF MATH_A_L
    CLRF MATH_A_H
    MOVLW 10
    CALL MULTIPLY_16x8
    BANKSEL RES_0
    MOVF RES_0, W
    BANKSEL INPUT_HUNDREDTHS
    ADDWF INPUT_HUNDREDTHS, W
    BANKSEL TARGET_TEMP_FRAC
    MOVWF TARGET_TEMP_FRAC
    
    ; Exit Loop
    BANKSEL INPUT_MODE
    BCF INPUT_MODE, 0
    RETURN

REJECT_VALUE:
    ; Value out of range (< 10.0 or > 50.0)
    ; Do NOT save, just exit input mode
    BANKSEL INPUT_MODE
    BCF INPUT_MODE, 0
    RETURN

; Display Input Buffer
DISPLAY_INPUT_BUFFER:
    ; Map Variables to Display Digits
    ; R2.1.2-2: Format XX.X (2 integer + 1 fraction)
    
    ; Digit 1: Tens
    ; If TENS is 0, show Blank (10)
    BANKSEL INPUT_TENS
    MOVF INPUT_TENS, W
    MOVWF TENS_DIGIT
    
    SUBLW 0
    BTFSS STATUS, 2 ; Z=1 if TENS=0
    GOTO CHECK_ONES
    
    ; TENS is 0, make it Blank (10)
    MOVLW 10
    MOVWF TENS_DIGIT
    
CHECK_ONES:
    BANKSEL INPUT_ONES
    MOVF INPUT_ONES, W
    MOVWF ONES_DIGIT
    
    ; Enable DP always in input mode
    BANKSEL SHOW_DP
    BSF SHOW_DP, 0
    
    ; 2 fractional digits (tenths and hundredths)
    BANKSEL INPUT_TENTHS
    MOVF INPUT_TENTHS, W
    MOVWF TENTHS_DIGIT
    
    BANKSEL INPUT_HUNDREDTHS
    MOVF INPUT_HUNDREDTHS, W
    MOVWF HUNDREDTHS_DIGIT
    
    RETURN

; Scan Keypad (Hardcoded Map)
SCAN_KEYPAD:
    BANKSEL KEY_VAL
    MOVLW 255
    MOVWF KEY_VAL
    
    ; Col 1 (RB4)
    BANKSEL PORTB
    BSF PORTB, 5
    BSF PORTB, 6
    BSF PORTB, 7
    BCF PORTB, 4
    CALL KEYPAD_DELAY
    BTFSS PORTB, 0 ; Row 1 (1)
    RETLW 1
    BTFSS PORTB, 1 ; Row 2 (4)
    RETLW 4
    BTFSS PORTB, 2 ; Row 3 (7)
    RETLW 7
    BTFSS PORTB, 3 ; Row 4 (*)
    RETLW 10
    
    ; Col 2 (RB5)
    BANKSEL PORTB
    BSF PORTB, 4
    BCF PORTB, 5
    CALL KEYPAD_DELAY
    BTFSS PORTB, 0 ; Row 1 (2)
    RETLW 2
    BTFSS PORTB, 1 ; Row 2 (5)
    RETLW 5
    BTFSS PORTB, 2 ; Row 3 (8)
    RETLW 8
    BTFSS PORTB, 3 ; Row 4 (0)
    RETLW 0
    
    ; Col 3 (RB6)
    BANKSEL PORTB
    BSF PORTB, 5
    BCF PORTB, 6
    CALL KEYPAD_DELAY
    BTFSS PORTB, 0 ; Row 1 (3)
    RETLW 3
    BTFSS PORTB, 1 ; Row 2 (6)
    RETLW 6
    BTFSS PORTB, 2 ; Row 3 (9)
    RETLW 9
    BTFSS PORTB, 3 ; Row 4 (#)
    RETLW 11
    
    ; Col 4 (RB7)
    BANKSEL PORTB
    BSF PORTB, 6
    BCF PORTB, 7
    CALL KEYPAD_DELAY
    BTFSS PORTB, 0 ; Row 1 (A)
    RETLW 12
    BTFSS PORTB, 1 ; Row 2 (B)
    RETLW 13
    BTFSS PORTB, 2 ; Row 3 (C)
    RETLW 14
    BTFSS PORTB, 3 ; Row 4 (D)
    RETLW 15
    
    ; None
    MOVLW 255
    MOVWF KEY_VAL
    RETURN

; Helper: Converts W to TENS_DIGIT and returns ONES in W
GET_DIGITS:
    CLRF TENS_DIGIT
    MOVWF MATH_A_L ; Use MATH_A_L as temp
DIGIT_DIV_LOOP:
    MOVLW 10
    SUBWF MATH_A_L, W
    BTFSS STATUS, 0
    GOTO DIGIT_DIV_DONE
    MOVWF MATH_A_L
    INCF TENS_DIGIT, F
    GOTO DIGIT_DIV_LOOP
DIGIT_DIV_DONE:
    MOVF MATH_A_L, W
    RETURN

; Display N Frames
; Input: W = Number of frames
DISPLAY_N_FRAMES:
    BANKSEL FRAME_COUNT
    MOVWF FRAME_COUNT
FRAME_LOOP:
    CALL DISPLAY_ONE_FRAME
    
    ; --- Periodic Temperature Check ---
    BANKSEL TEMP_CHECK_COUNT
    DECFSZ TEMP_CHECK_COUNT, F
    GOTO SKIP_TEMP_CHECK
    
    ; Reload Counter
    MOVLW 50
    MOVWF TEMP_CHECK_COUNT
    
    ; Update Control Loop
    CALL READ_TEMPERATURE
    CALL CONTROL_TEMP
    
SKIP_TEMP_CHECK:
    BANKSEL FRAME_COUNT
    DECFSZ FRAME_COUNT, F
    GOTO FRAME_LOOP
    RETURN

; Display One Frame (Multiplex 4 digits once)
DISPLAY_ONE_FRAME:
    ; --- Digit 1: Tens (RC0) ---
    CALL OFF_ALL
    BANKSEL TENS_DIGIT
    MOVF TENS_DIGIT, W
    CALL GET_SEGMENT_CODE
    CALL SEND_TO_PORTD
    BANKSEL PORTC
    MOVF PORTC, W
    ANDLW 0xF0
    IORLW 0x01          ; RC0
    MOVWF PORTC
    CALL SHORT_DELAY
    
    ; --- Digit 2: Ones (RC1) + DP ---
    CALL OFF_ALL
    BANKSEL ONES_DIGIT
    MOVF ONES_DIGIT, W
    CALL GET_SEGMENT_CODE
    CALL SEND_TO_PORTD
    ; Add Decimal Point (RD7)
    BANKSEL SHOW_DP
    BTFSC SHOW_DP, 0
    BSF PORTD, 7
    BANKSEL PORTC
    MOVF PORTC, W
    ANDLW 0xF0
    IORLW 0x02          ; RC1
    MOVWF PORTC
    CALL SHORT_DELAY
    
    ; --- Digit 3: Tenths (RC2) ---
    CALL OFF_ALL
    BANKSEL TENTHS_DIGIT
    MOVF TENTHS_DIGIT, W
    CALL GET_SEGMENT_CODE
    CALL SEND_TO_PORTD
    BANKSEL PORTC
    MOVF PORTC, W
    ANDLW 0xF0
    IORLW 0x04          ; RC2
    MOVWF PORTC
    CALL SHORT_DELAY
    
    ; --- Digit 4: Hundredths (RC3) ---
    CALL OFF_ALL
    BANKSEL HUNDREDTHS_DIGIT
    MOVF HUNDREDTHS_DIGIT, W
    CALL GET_SEGMENT_CODE
    CALL SEND_TO_PORTD
    BANKSEL PORTC
    MOVF PORTC, W
    ANDLW 0xF0
    IORLW 0x08          ; RC3
    MOVWF PORTC
    CALL SHORT_DELAY
    RETURN

; Display Temperature on 7-Segment
; D1 (RC0): Tens
; D2 (RC1): Ones + DP
; D3 (RC2): Tenths
; D4 (RC3): Hundredths
DISPLAY_TEMPERATURE:
    BANKSEL DISPLAY_COUNT
    MOVLW 0xC8
    MOVWF DISPLAY_COUNT
    
DISPLAY_LOOP:
    ; --- Digit 1: Tens (RC0) ---
    CALL OFF_ALL
    BANKSEL TENS_DIGIT
    MOVF TENS_DIGIT, W
    CALL GET_SEGMENT_CODE
    CALL SEND_TO_PORTD
    BANKSEL PORTC
    MOVF PORTC, W
    ANDLW 0xF0
    IORLW 0x01          ; RC0
    MOVWF PORTC
    CALL SHORT_DELAY
    
    ; --- Digit 2: Ones (RC1) + DP ---
    CALL OFF_ALL
    BANKSEL ONES_DIGIT
    MOVF ONES_DIGIT, W
    CALL GET_SEGMENT_CODE
    CALL SEND_TO_PORTD
    ; Add Decimal Point (RD7)
    BANKSEL PORTD
    BSF PORTD, 7
    BANKSEL PORTC
    MOVF PORTC, W
    ANDLW 0xF0
    IORLW 0x02          ; RC1
    MOVWF PORTC
    CALL SHORT_DELAY
    
    ; --- Digit 3: Tenths (RC2) ---
    CALL OFF_ALL
    BANKSEL TENTHS_DIGIT
    MOVF TENTHS_DIGIT, W
    CALL GET_SEGMENT_CODE
    CALL SEND_TO_PORTD
    BANKSEL PORTC
    MOVF PORTC, W
    ANDLW 0xF0
    IORLW 0x04          ; RC2
    MOVWF PORTC
    CALL SHORT_DELAY
    
    ; --- Digit 4: Hundredths (RC3) ---
    CALL OFF_ALL
    BANKSEL HUNDREDTHS_DIGIT
    MOVF HUNDREDTHS_DIGIT, W
    CALL GET_SEGMENT_CODE
    CALL SEND_TO_PORTD
    BANKSEL PORTC
    MOVF PORTC, W
    ANDLW 0xF0
    IORLW 0x08          ; RC3
    MOVWF PORTC
    CALL SHORT_DELAY
    
    BANKSEL DISPLAY_COUNT
    DECFSZ DISPLAY_COUNT, F
    GOTO DISPLAY_LOOP
    
    CALL OFF_ALL
    RETURN

OFF_ALL:
    BANKSEL PORTC
    MOVF PORTC, W
    ANDLW 0xF0      ; Keep RC4-RC7 (Heater/Cooler), Clear RC0-RC3 (Digits)
    MOVWF PORTC
    BANKSEL PORTD
    CLRF PORTD
    RETURN

SEND_TO_PORTD:
    ; No shift needed (segments on RD0-RD6)
    BANKSEL TEMP_LOW
    MOVWF TEMP_LOW
    MOVF TEMP_LOW, W
    BANKSEL PORTD
    MOVWF PORTD
    RETURN

; Get 7-Segment Code from Table
GET_SEGMENT_CODE:
    BANKSEL TEMP_LOW
    MOVWF TEMP_LOW
    MOVLW HIGH(SEGMENT_TABLE)
    MOVWF PCLATH
    MOVF TEMP_LOW, W
    CALL SEGMENT_TABLE
    RETURN

; 7-Segment Lookup Table (Common Cathode)
; Standard codes (shifted by 1 in display routine)
SEGMENT_TABLE:
    ADDWF PCL, F
    RETLW 0x3F  ; 0
    RETLW 0x06  ; 1
    RETLW 0x5B  ; 2
    RETLW 0x4F  ; 3
    RETLW 0x66  ; 4
    RETLW 0x6D  ; 5
    RETLW 0x7D  ; 6
    RETLW 0x07  ; 7
    RETLW 0x7F  ; 8
    RETLW 0x6F  ; 9
    RETLW 0x00  ; 10 (Blank)

; Short Delay
SHORT_DELAY:
    BANKSEL DELAY_COUNT
    MOVLW 0xFF
    MOVWF DELAY_COUNT
SHORT_DELAY_LOOP:
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    DECFSZ DELAY_COUNT, F
    GOTO SHORT_DELAY_LOOP
    RETURN

; Keypad Delay (Longer for stability)
KEYPAD_DELAY:
    BANKSEL DELAY_COUNT
    MOVLW 0x80 ; Increased for better debounce (was 0x50)
    MOVWF DELAY_COUNT
KEYPAD_DELAY_LOOP:
    NOP
    NOP
    NOP
    NOP
    DECFSZ DELAY_COUNT, F
    GOTO KEYPAD_DELAY_LOOP
    RETURN

; Main Delay
DELAY:
    BANKSEL DELAY_COUNT
    MOVLW 0x32
    MOVWF DELAY_COUNT
DELAY_OUTER:
    MOVLW 0xFF
    MOVWF DELAY_COUNT2
DELAY_INNER:
    DECFSZ DELAY_COUNT2, F
    GOTO DELAY_INNER
    DECFSZ DELAY_COUNT, F
    GOTO DELAY_OUTER
    RETURN

; ==============================================================================
; UART COMMUNICATION ROUTINES (R2.1.4-1)
; ==============================================================================

; Check UART for incoming data and process commands
CHECK_UART:
    BANKSEL PIR1
    BTFSS PIR1, 5       ; RCIF - Check if data received
    RETURN              ; No data, return
    
    ; Check for overrun error
    BANKSEL RCSTA
    BTFSS RCSTA, 1      ; OERR
    GOTO READ_UART_DATA
    
    ; Clear overrun error
    BCF RCSTA, 4        ; CREN = 0
    BSF RCSTA, 4        ; CREN = 1
    RETURN
    
READ_UART_DATA:
    ; Read received byte
    BANKSEL RCREG
    MOVF RCREG, W
    BANKSEL UART_DATA
    MOVWF UART_DATA
    
    ; Process command based on received byte
    ; Check bits 7:6 to determine command type
    
    ; Check if SET command (bit 7 = 1)
    BTFSC UART_DATA, 7
    GOTO UART_SET_CMD
    
    ; GET command (bit 7 = 0)
    GOTO UART_GET_CMD

UART_GET_CMD:
    ; 0x01: Get desired temp fraction
    MOVF UART_DATA, W
    SUBLW 0x01
    BTFSC STATUS, 2
    GOTO UART_GET_DESIRED_FRAC
    
    ; 0x02: Get desired temp integer
    MOVF UART_DATA, W
    SUBLW 0x02
    BTFSC STATUS, 2
    GOTO UART_GET_DESIRED_INT
    
    ; 0x03: Get ambient temp fraction
    MOVF UART_DATA, W
    SUBLW 0x03
    BTFSC STATUS, 2
    GOTO UART_GET_AMBIENT_FRAC
    
    ; 0x04: Get ambient temp integer
    MOVF UART_DATA, W
    SUBLW 0x04
    BTFSC STATUS, 2
    GOTO UART_GET_AMBIENT_INT
    
    ; 0x05: Get fan speed
    MOVF UART_DATA, W
    SUBLW 0x05
    BTFSC STATUS, 2
    GOTO UART_GET_FAN_SPEED
    
    ; Unknown command, ignore
    RETURN

UART_GET_DESIRED_FRAC:
    BANKSEL TARGET_TEMP_FRAC
    MOVF TARGET_TEMP_FRAC, W
    CALL UART_SEND
    RETURN

UART_GET_DESIRED_INT:
    BANKSEL TARGET_TEMP_INT
    MOVF TARGET_TEMP_INT, W
    CALL UART_SEND
    RETURN

UART_GET_AMBIENT_FRAC:
    BANKSEL FRAC_TEMP
    MOVF FRAC_TEMP, W
    CALL UART_SEND
    RETURN

UART_GET_AMBIENT_INT:
    BANKSEL AMBIENT_TEMP
    MOVF AMBIENT_TEMP, W
    CALL UART_SEND
    RETURN

UART_GET_FAN_SPEED:
    BANKSEL FAN_SPEED_STORE
    MOVF FAN_SPEED_STORE, W
    CALL UART_SEND
    RETURN

UART_SET_CMD:
    ; Check bit 6 to determine frac (0) or int (1)
    BANKSEL UART_DATA
    BTFSC UART_DATA, 6
    GOTO UART_SET_DESIRED_INT
    
    ; 10xxxxxx: Set desired temp fraction
    ; Extract 6-bit value (mask with 0x3F)
    MOVF UART_DATA, W
    ANDLW 0x3F
    BANKSEL TARGET_TEMP_FRAC
    MOVWF TARGET_TEMP_FRAC
    RETURN

UART_SET_DESIRED_INT:
    ; 11xxxxxx: Set desired temp integer
    ; Extract 6-bit value (mask with 0x3F)
    BANKSEL UART_DATA
    MOVF UART_DATA, W
    ANDLW 0x3F
    BANKSEL TARGET_TEMP_INT
    MOVWF TARGET_TEMP_INT
    RETURN

; Send byte in W via UART
UART_SEND:
    BANKSEL UART_DATA
    MOVWF UART_DATA     ; Save byte to send
    
UART_WAIT_TX:
    BANKSEL TXSTA
    BTFSS TXSTA, 1      ; TRMT - Wait for TSR empty
    GOTO UART_WAIT_TX
    
    BANKSEL UART_DATA
    MOVF UART_DATA, W
    BANKSEL TXREG
    MOVWF TXREG         ; Send byte
    RETURN

; ==============================================================================
; PIN LAYOUT SUMMARY
; ==============================================================================
;
; PORTA:
;   RA0 (AN0)   : Temperature Sensor Input (LM35)
;   RA4 (T0CKI) : Tachometer Input (Fan Speed Pulse)
;
; PORTB (Keypad 4x4):
;   RB0 (Input) : Row 1
;   RB1 (Input) : Row 2
;   RB2 (Input) : Row 3
;   RB3 (Input) : Row 4
;   RB4 (Output): Column 1
;   RB5 (Output): Column 2
;   RB6 (Output): Column 3
;   RB7 (Output): Column 4
;
; PORTC (Control & Display Digits):
;   RC0 (Output): Display Digit 1 (Tens)
;   RC1 (Output): Display Digit 2 (Ones)
;   RC2 (Output): Display Digit 3 (Tenths)
;   RC3 (Output): Display Digit 4 (Hundredths)
;   RC4 (Output): Heater Control
;   RC5 (Output): Cooler Control
;
; PORTD (7-Segment Display Segments):
;   RD0 (Output): Segment a
;   RD1 (Output): Segment b
;   RD2 (Output): Segment c
;   RD3 (Output): Segment d
;   RD4 (Output): Segment e
;   RD5 (Output): Segment f
;   RD6 (Output): Segment g
;   RD7 (Output): Decimal Point (DP)
;
; ==============================================================================

END