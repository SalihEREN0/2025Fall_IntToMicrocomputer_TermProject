;====================================================================
; BOARD 1: HOME AIR CONDITIONER SYSTEM 
;====================================================================
PROCESSOR 16F877A
#include <xc.inc>

; Configuration
CONFIG FOSC = HS        ; High-Speed Crystal Oscillator
CONFIG WDTE = OFF       ; Watchdog Timer Disabled
CONFIG PWRTE = ON       ; Power-up Timer Enabled
CONFIG BOREN = ON       ; Brown-out Reset Enabled
CONFIG LVP = OFF        ; Low-Voltage Programming Disabled
CONFIG CPD = OFF        ; Data EEPROM Memory Code Protection Off
CONFIG WRT = OFF        ; Flash Program Memory Write Enable Off
CONFIG CP = OFF         ; Flash Program Memory Code Protection Off

; Constants
#define HEATER_PIN 4      ; RC4 (Output for Heater Relay/LED)
#define COOLER_PIN 5      ; RC5 (Output for Cooler Relay/LED)

;====================================================================
; VARIABLES
;====================================================================
PSECT udata_bank0
    ; Core System Data
    TARGET_TEMP_INT:   DS 1   ; [R2.1.1-1] Desired Temp Integer part
    TARGET_TEMP_FRAC:  DS 1   ; [R2.1.1-1] Desired Temp Fractional part
    AMBIENT_TEMP:      DS 1   ; [R2.1.1-4] Measured Ambient Temp Integer
    FRAC_TEMP:         DS 1   ; Measured Ambient Temp Fraction
    FAN_SPEED_STORE:   DS 1   ; [R2.1.1-5] Fan Speed (RPS)

    ; Display & Logic Variables
    VAL_INT:           DS 1   ; Temporary holder for Integer to display
    VAL_FRAC:          DS 1   ; Temporary holder for Fraction to display
    TEMP_LOW:          DS 1   ; Low byte temp storage
    DELAY_COUNT:       DS 1   ; Counter for delay loops
    DELAY_COUNT2:      DS 1   ; Secondary counter for nested loops
    TENS_DIGIT:        DS 1   ; Tens digit storage (0-9)
    ONES_DIGIT:        DS 1   ; Ones digit storage (0-9)
    TENTHS_DIGIT:      DS 1   ; Tenths digit storage (0.x)
    HUNDREDTHS_DIGIT:  DS 1   ; Hundredths digit storage (0.0x)
    FRAME_COUNT:       DS 1   ; Counter for multiplexing frames
    TEMP_CHECK_COUNT:  DS 1   ; Counter to slow down temp sampling
    SHOW_DP:           DS 1   ; Flag: 1 = Show Decimal Point, 0 = Hide

    ; Keypad Input Variables
    INPUT_MODE:        DS 1   ; Bit 0: 1=Input Active, 0=Display Mode
    KEY_VAL:           DS 1   ; Value of pressed key (0-15, 255=None)
    INPUT_TENS:        DS 1   ; Input buffer: Tens
    INPUT_ONES:        DS 1   ; Input buffer: Ones
    INPUT_TENTHS:      DS 1   ; Input buffer: Tenths
    INPUT_HUNDREDTHS:  DS 1   ; Input buffer: Hundredths
    IS_FRAC_MODE:      DS 1   ; Flag: Are we entering decimals?
    FRAC_INDEX:        DS 1   ; Position index for decimal entry
    LAST_KEY:          DS 1   ; Debounce: last key pressed
    
    ; Math Variables (16/24 bit arithmetic helpers)
    RES_0: DS 1               ; Result Byte 0 (LSB)
    RES_1: DS 1               ; Result Byte 1
    RES_2: DS 1               ; Result Byte 2 (MSB)
    MATH_A_L: DS 1            ; Operand A Low Byte
    MATH_A_H: DS 1            ; Operand A High Byte
    MATH_COUNT: DS 1          ; Loop counter for math ops
    MATH_TEMP: DS 1           ; Temp register for math
    DIVISOR_L: DS 1           ; Divisor Low Byte
    DIVISOR_H: DS 1           ; Divisor High Byte
    REM_0: DS 1               ; Remainder Byte 0
    REM_1: DS 1               ; Remainder Byte 1

    ; UART Variables
    UART_DATA:         DS 1   ; Received Data Buffer
    UART_READY:        DS 1   ; Flag: 1=Data Ready to process, 0=Empty
    UART_TEMP_REG:     DS 1   ; Temporary variable for ISR handling

    ; Interrupt Context Saving
    W_TEMP:            DS 1   ; Save W register
    STATUS_TEMP:       DS 1   ; Save STATUS register
    PCLATH_TEMP:       DS 1   ; Save PCLATH register

;====================================================================
; VECTORS
;====================================================================
PSECT resetVec,class=CODE,delta=2
    GOTO MAIN                 ; Reset Vector (0x0000)

PSECT intVec,class=CODE,delta=2,abs
ORG 0x0004
    GOTO ISR                  ; Interrupt Vector (0x0004)

;====================================================================
; ISR (INTERRUPT SERVICE ROUTINE)
;====================================================================
PSECT code
ISR:
    ; Context Save (Critical for reliable interrupts)
    MOVWF   W_TEMP            ; Save W
    SWAPF   STATUS, W
    MOVWF   STATUS_TEMP       ; Save STATUS
    CLRF    STATUS            ; Force Bank 0
    MOVF    PCLATH, W
    MOVWF   PCLATH_TEMP       ; Save PCLATH
    CLRF    PCLATH            ; Ensure Page 0

    ; --- 1. UART RX INTERRUPT CHECK ---
    BANKSEL PIR1
    BTFSS   PIR1, 5         ; Check RCIF (UART RX Interrupt Flag)
    GOTO    CHECK_EXT_INT   ; If not set, check RB0 Interrupt

    ; Check Overrun Error
    BANKSEL RCSTA
    BTFSC   RCSTA, 1        ; Check OERR (Overrun Error bit)
    GOTO    UART_OERR_RESET ; If error, reset receiver

    ; Read Data
    BANKSEL RCREG
    MOVF    RCREG, W        ; Reading RCREG clears RCIF automatically
    BANKSEL UART_DATA
    MOVWF   UART_DATA       ; Store received byte in RAM
    MOVLW   1
    MOVWF   UART_READY      ; Set Flag to indicate data is ready
    GOTO    CHECK_EXT_INT

UART_OERR_RESET:
    BCF     RCSTA, 4        ; Clear CREN (Disable Rx)
    BSF     RCSTA, 4        ; Set CREN (Enable Rx) to reset OERR logic
    GOTO    CHECK_EXT_INT

    ; --- 2. EXTERNAL INTERRUPT (RB0) CHECK ---
CHECK_EXT_INT:
    BANKSEL INTCON
    BTFSS   INTCON, 1       ; Check INTF (External Interrupt Flag)
    GOTO    ISR_EXIT        ; If not set, exit ISR

    ; Handle 'A' Button Press logic (mapped to RB0 interrupt)
    BANKSEL INPUT_MODE
    BSF     INPUT_MODE, 0   ; Set Input Mode flag
    BANKSEL INTCON
    BCF     INTCON, 1       ; Clear INTF to allow future interrupts

ISR_EXIT:
    ; Context Restore
    MOVF    PCLATH_TEMP, W
    MOVWF   PCLATH          ; Restore PCLATH
    SWAPF   STATUS_TEMP, W
    MOVWF   STATUS          ; Restore STATUS
    SWAPF   W_TEMP, F
    SWAPF   W_TEMP, W       ; Restore W
    RETFIE                  ; Return from Interrupt

;====================================================================
; MAIN PROGRAM
;====================================================================
MAIN:
    CALL    DELAY           ; Power-up stability delay
    CALL    DELAY
    BANKSEL INTCON
    CLRF    INTCON          ; Disable interrupts during init
    CALL    INIT_SYSTEM     ; Initialize ports and peripherals

MAIN_LOOP:
    ; 1. Check Keypad Input Mode
    BANKSEL INPUT_MODE
    BTFSC   INPUT_MODE, 0     ; Is Input Mode Active?
    CALL    HANDLE_INPUT_MODE ; Yes, handle keypad entry

    ; 2. Check UART Commands
    CALL    CHECK_UART_FLAG   ; Check if PC sent data

    ; 3. Ambient Temperature Handling
    CALL    READ_TEMPERATURE  ; Read ADC and convert to Temp
    CALL    CONTROL_TEMP      ; Update Heater/Cooler outputs
    
    BANKSEL AMBIENT_TEMP
    MOVF    AMBIENT_TEMP, W
    MOVWF   VAL_INT
    MOVF    FRAC_TEMP, W
    MOVWF   VAL_FRAC
    CALL    CONVERT_TO_DIGITS ; Prepare digits for display
    
    MOVLW   45
    CALL    DISPLAY_N_FRAMES ; Refresh display (Shows Ambient)
    
    BANKSEL INPUT_MODE
    BTFSC   INPUT_MODE, 0
    GOTO    MAIN_LOOP        ; If input mode triggered, loop back
    
    MOVLW   45
    CALL    DISPLAY_N_FRAMES ; Continue displaying
    
    ; 4. Target Temperature Handling
    BANKSEL TARGET_TEMP_INT
    MOVF    TARGET_TEMP_INT, W
    MOVWF   VAL_INT
    MOVF    TARGET_TEMP_FRAC, W
    MOVWF   VAL_FRAC
    CALL    CONVERT_TO_DIGITS
    
    MOVLW   45
    CALL    DISPLAY_N_FRAMES ; Refresh display (Shows Target)
    MOVLW   45
    CALL    DISPLAY_N_FRAMES
    
    ; 5. Fan Speed Handling (RPS simulation)
    BANKSEL SHOW_DP
    CLRF    SHOW_DP          ; RPS is integer, hide Decimal Point
    
    BANKSEL TMR0
    MOVF    TMR0, W          ; Use TMR0 as random source for simulation
    MOVWF   MATH_TEMP
    BCF     STATUS, 0
    RRF     MATH_TEMP, F     ; Scale value down
    
    MOVF    MATH_TEMP, W
    BANKSEL FAN_SPEED_STORE
    MOVWF   FAN_SPEED_STORE  ; Store RPS for UART reporting
    
    CALL    CONVERT_RPS_TO_DIGITS
    
    MOVLW   45
    CALL    DISPLAY_N_FRAMES ; Refresh display (Shows Fan Speed)
    MOVLW   45
    CALL    DISPLAY_N_FRAMES
    
    BANKSEL SHOW_DP
    MOVLW   1
    MOVWF   SHOW_DP          ; Restore Decimal Point for Temp
    
    GOTO    MAIN_LOOP        ; Infinite Loop

;====================================================================
; SYSTEM INITIALIZATION
;====================================================================
INIT_SYSTEM:
    BANKSEL TRISA
    MOVLW   0xFF        ; Port A Inputs (Analog Sensors)
    MOVWF   TRISA
    
    MOVLW   0x0F        ; Port B: RB0-3 Input (Keypad Rows), RB4-7 Output (Cols)
    MOVWF   TRISB
    
    MOVLW   0x80        ; Port C: RC7(RX)=Input, RC6(TX)=Output, Others Output
    MOVWF   TRISC
    
    CLRF    TRISD       ; Port D Output (7-Segment Drivers)
    
    MOVLW   0x8E        ; ADCON1: Right Justified, AN0 Analog, others Digital
    MOVWF   ADCON1
    
    MOVLW   0x28        ; OPTION_REG: TMR0 Prescaler assignment
    MOVWF   OPTION_REG
    
    BANKSEL PORTA
    CLRF    PORTA       ; Clear latches
    CLRF    PORTB
    CLRF    PORTC
    CLRF    PORTD
    CLRF    AMBIENT_TEMP
    CLRF    FAN_SPEED_STORE
    CLRF    INPUT_MODE
    CLRF    UART_READY
    
    BANKSEL TARGET_TEMP_INT
    MOVLW   27
    MOVWF   TARGET_TEMP_INT   ; Default Target Temp = 27C
    CLRF    TARGET_TEMP_FRAC
    
    BANKSEL SHOW_DP
    MOVLW   1
    MOVWF   SHOW_DP           ; Enable Decimal Point by default
    
    BANKSEL TEMP_CHECK_COUNT
    MOVLW   50
    MOVWF   TEMP_CHECK_COUNT  ; Init sampling counter
    
    MOVLW   0x81        ; ADCON0: Fosc/32, Channel 0, ADC On
    MOVWF   ADCON0
    
    ; --- UART CONFIG (9600 Baud @ 4MHz) ---
    BANKSEL SPBRG
    MOVLW   25          ; SPBRG for 9600 baud
    MOVWF   SPBRG
    
    BANKSEL TXSTA
    MOVLW   0x24        ; TXEN=1 (Transmit Enable), BRGH=1 (High Speed)
    MOVWF   TXSTA
    
    BANKSEL RCSTA
    MOVLW   0x90        ; SPEN=1 (Serial Port Enable), CREN=1 (Receive Enable)
    MOVWF   RCSTA
    
    ; Clear UART Buffer
    BANKSEL RCREG
    MOVF    RCREG, W
    MOVF    RCREG, W
    
    ; Keypad Init Port B
    BANKSEL PORTB
    MOVLW   0xF0        ; Set columns high
    MOVWF   PORTB
    BCF     PORTB, 7    ; Prepare for scan
    
    ; --- INTERRUPT ENABLES ---
    BANKSEL PIE1
    BSF     PIE1, 5     ; RCIE: Enable UART RX Interrupt
    
    BANKSEL INTCON
    BSF     INTCON, 4   ; INTE: Enable RB0 External Interrupt
    BSF     INTCON, 6   ; PEIE: Enable Peripheral Interrupts
    BSF     INTCON, 7   ; GIE: Enable Global Interrupts
    
    CALL    DELAY
    BANKSEL PORTC
    CLRF    PORTC
    RETURN

;====================================================================
; MATH & ADC ROUTINES
;====================================================================
READ_TEMPERATURE:
    BANKSEL ADCON0
    MOVLW   0x81
    MOVWF   ADCON0
    CALL    SHORT_DELAY
    CALL    SHORT_DELAY
    BSF     ADCON0, 2       ; GO/DONE = 1 (Start Conversion)
WAIT_ADC:
    BTFSC   ADCON0, 2       ; Wait for GO/DONE to clear
    GOTO    WAIT_ADC
    
    ; Read Result (10-bit)
    BANKSEL ADRESL
    MOVF    ADRESL, W
    BANKSEL MATH_A_L
    MOVWF   MATH_A_L
    BANKSEL ADRESH
    MOVF    ADRESH, W
    BANKSEL MATH_A_H
    MOVWF   MATH_A_H
    
    ; Convert ADC to Voltage/Temp (Fixed Point Math)
    MOVLW   244             ; Scaling factor
    CALL    MULTIPLY_16x8
    
    BANKSEL MATH_A_L
    MOVF    MATH_A_L, W
    BANKSEL RES_1
    ADDWF   RES_1, F
    BTFSC   STATUS, 0
    INCF    RES_2, F
    
    BANKSEL MATH_A_H
    MOVF    MATH_A_H, W
    BANKSEL RES_2
    ADDWF   RES_2, F
    
    BANKSEL DIVISOR_L
    MOVLW   0xFF 
    MOVWF   DIVISOR_L
    MOVLW   0x03 
    MOVWF   DIVISOR_H       ; Division logic (approx /1023)
    CALL    DIVIDE_24x16
    
    BANKSEL RES_0
    MOVF    RES_0, W
    BANKSEL AMBIENT_TEMP
    MOVWF   AMBIENT_TEMP    ; Save Integer Part
    
    ; Calculate Fraction
    BANKSEL REM_0
    MOVF    REM_0, W
    BANKSEL MATH_A_L
    MOVWF   MATH_A_L
    BANKSEL REM_1
    MOVF    REM_1, W
    BANKSEL MATH_A_H
    MOVWF   MATH_A_H
    MOVLW   100
    CALL    MULTIPLY_16x8   ; Scale remainder
    
    BANKSEL RES_0
    MOVLW   0xFF
    ADDWF   RES_0, F
    BTFSC   STATUS, 0
    CALL    INC_RES_1
    MOVLW   0x01
    ADDWF   RES_1, F
    BTFSC   STATUS, 0
    INCF    RES_2, F
    
    BANKSEL DIVISOR_L
    MOVLW   0xFF
    MOVWF   DIVISOR_L
    MOVLW   0x03
    MOVWF   DIVISOR_H
    CALL    DIVIDE_24x16
    
    BANKSEL RES_0
    MOVF    RES_0, W
    BANKSEL FRAC_TEMP
    MOVWF   FRAC_TEMP       ; Save Fractional Part
    RETURN

MULTIPLY_16x8:
    BANKSEL MATH_COUNT
    MOVWF   MATH_COUNT
    CLRF    RES_0
    CLRF    RES_1
    CLRF    RES_2
    MOVLW   8
    MOVWF   MATH_TEMP 
MULT_LOOP:
    BCF     STATUS, 0
    RLF     RES_0, F
    RLF     RES_1, F
    RLF     RES_2, F
    BCF     STATUS, 0
    RLF     MATH_COUNT, F
    BTFSS   STATUS, 0
    GOTO    SKIP_ADD
    MOVF    MATH_A_L, W
    ADDWF   RES_0, F
    BTFSC   STATUS, 0
    CALL    INC_RES_1
    MOVF    MATH_A_H, W
    ADDWF   RES_1, F
    BTFSC   STATUS, 0
    INCF    RES_2, F
SKIP_ADD:
    DECFSZ  MATH_TEMP, F
    GOTO    MULT_LOOP
    RETURN

INC_RES_1:
    INCF    RES_1, F
    BTFSC   STATUS, 2 
    INCF    RES_2, F
    RETURN

DIVIDE_24x16:
    BANKSEL REM_0
    CLRF    REM_0
    CLRF    REM_1
    MOVLW   24
    MOVWF   MATH_COUNT
DIV_LOOP:
    BCF     STATUS, 0
    RLF     RES_0, F
    RLF     RES_1, F
    RLF     RES_2, F
    RLF     REM_0, F
    RLF     REM_1, F
    MOVF    DIVISOR_H, W
    SUBWF   REM_1, W
    BTFSS   STATUS, 0 
    GOTO    NEXT_BIT
    BTFSS   STATUS, 2 
    GOTO    SUBTRACT
    MOVF    DIVISOR_L, W
    SUBWF   REM_0, W
    BTFSS   STATUS, 0 
    GOTO    NEXT_BIT
SUBTRACT:
    MOVF    DIVISOR_L, W
    SUBWF   REM_0, F
    BTFSS   STATUS, 0
    DECF    REM_1, F
    MOVF    DIVISOR_H, W
    SUBWF   REM_1, F
    BSF     RES_0, 0
NEXT_BIT:
    DECFSZ  MATH_COUNT, F
    GOTO    DIV_LOOP
    RETURN

CONTROL_TEMP:
    BANKSEL AMBIENT_TEMP
    MOVF    AMBIENT_TEMP, W
    BANKSEL TARGET_TEMP_INT
    SUBWF   TARGET_TEMP_INT, W
    BTFSC   STATUS, 2         ; If Zero flag set, Int parts equal
    GOTO    CHECK_FRACTION      
    BTFSS   STATUS, 0         ; If Carry clear, Target < Ambient
    GOTO    TOO_HOT             
    GOTO    TOO_COLD
CHECK_FRACTION:
    BANKSEL FRAC_TEMP
    MOVF    FRAC_TEMP, W
    BANKSEL TARGET_TEMP_FRAC
    SUBWF   TARGET_TEMP_FRAC, W 
    BTFSC   STATUS, 2         ; Exact match
    GOTO    TEMP_OK
    BTFSS   STATUS, 0         ; Target < Ambient
    GOTO    TOO_HOT
    GOTO    TOO_COLD
TOO_COLD:
    BANKSEL PORTC
    BSF     PORTC, HEATER_PIN   ; Turn Heater ON
    BCF     PORTC, COOLER_PIN   ; Turn Cooler OFF
    RETURN
TOO_HOT:
    BANKSEL PORTC
    BCF     PORTC, HEATER_PIN   ; Turn Heater OFF
    BSF     PORTC, COOLER_PIN   ; Turn Cooler ON
    RETURN
TEMP_OK:
    BANKSEL PORTC
    BCF     PORTC, HEATER_PIN   ; Both OFF (Hysteresis/Deadband ideal)
    BCF     PORTC, COOLER_PIN
    RETURN

CONVERT_TO_DIGITS:
    ; Splits values into TENS, ONES, TENTHS, HUNDREDTHS for display
    BANKSEL VAL_INT
    MOVF    VAL_INT, W
    CALL    GET_DIGITS
    MOVWF   ONES_DIGIT
    MOVF    TENS_DIGIT, W
    MOVWF   MATH_TEMP 
    BANKSEL VAL_FRAC
    MOVF    VAL_FRAC, W
    CALL    GET_DIGITS
    MOVWF   HUNDREDTHS_DIGIT
    MOVF    TENS_DIGIT, W
    MOVWF   TENTHS_DIGIT
    MOVF    MATH_TEMP, W
    MOVWF   TENS_DIGIT
    RETURN

CONVERT_RPS_TO_DIGITS:
    BANKSEL TENS_DIGIT
    CLRF    TENS_DIGIT        
    CLRF    ONES_DIGIT        
    CLRF    TENTHS_DIGIT      
    CLRF    HUNDREDTHS_DIGIT  
RPS_HUND_LOOP:
    MOVLW   100
    SUBWF   MATH_TEMP, W
    BTFSS   STATUS, 0
    GOTO    RPS_HUND_DONE
    MOVWF   MATH_TEMP
    INCF    ONES_DIGIT, F
    GOTO    RPS_HUND_LOOP
RPS_HUND_DONE:
RPS_TENS_LOOP:
    MOVLW   10
    SUBWF   MATH_TEMP, W
    BTFSS   STATUS, 0
    GOTO    RPS_TENS_DONE
    MOVWF   MATH_TEMP
    INCF    TENTHS_DIGIT, F
    GOTO    RPS_TENS_LOOP
RPS_TENS_DONE:
    MOVF    MATH_TEMP, W
    MOVWF   HUNDREDTHS_DIGIT
    RETURN

;====================================================================
; KEYPAD & INPUT ROUTINES
;====================================================================
HANDLE_INPUT_MODE:
    BANKSEL INTCON
    BCF     INTCON, 7  ; Disable GIE to prevent interruptions
    BANKSEL PORTC
    BCF     PORTC, 4   ; Turn off AC loads for safety/power during input
    BCF     PORTC, 5 
    BANKSEL INPUT_TENS
    CLRF    INPUT_TENS
    CLRF    INPUT_ONES
    CLRF    INPUT_TENTHS
    CLRF    INPUT_HUNDREDTHS
    CLRF    IS_FRAC_MODE
    CLRF    FRAC_INDEX
    MOVLW   255
    MOVWF   LAST_KEY
INPUT_LOOP:
    CALL    DISPLAY_INPUT_BUFFER ; Show what is being typed
    CALL    DISPLAY_ONE_FRAME
    CALL    SCAN_KEYPAD          ; Scan Matrix
    BANKSEL KEY_VAL
    MOVWF   KEY_VAL
    BANKSEL KEY_VAL
    MOVF    KEY_VAL, W
    BANKSEL LAST_KEY
    XORWF   LAST_KEY, W
    BTFSC   STATUS, 2  ; Debounce: If key same as last frame, skip
    GOTO    INPUT_LOOP_CONTINUE 
    BANKSEL KEY_VAL
    MOVF    KEY_VAL, W
    BANKSEL LAST_KEY
    MOVWF   LAST_KEY
    SUBLW   255        ; Check if no key pressed
    BTFSC   STATUS, 2
    GOTO    INPUT_LOOP_CONTINUE
    CALL    PROCESS_KEY
    CALL    DELAY
    MOVLW   3
    MOVWF   MATH_TEMP            
WAIT_KEY_RELEASE:
    CALL    DISPLAY_INPUT_BUFFER
    CALL    DISPLAY_ONE_FRAME
    CALL    DISPLAY_ONE_FRAME
    CALL    DISPLAY_ONE_FRAME
    CALL    SCAN_KEYPAD
    SUBLW   255
    BTFSS   STATUS, 2            ; Wait until key is released
    GOTO    WAIT_KEY_RESET       
    BANKSEL MATH_TEMP
    DECFSZ  MATH_TEMP, F
    GOTO    WAIT_KEY_RELEASE     
    GOTO    WAIT_KEY_DONE        
WAIT_KEY_RESET:
    MOVLW   3
    MOVWF   MATH_TEMP            
    GOTO    WAIT_KEY_RELEASE
WAIT_KEY_DONE:
    CALL    DELAY
    BANKSEL LAST_KEY
    MOVLW   255
    MOVWF   LAST_KEY
INPUT_LOOP_CONTINUE:
    BANKSEL INPUT_MODE
    BTFSS   INPUT_MODE, 0
    GOTO    EXIT_INPUT_MODE
    GOTO    INPUT_LOOP
EXIT_INPUT_MODE:
    BANKSEL PORTB
    MOVLW   0xF0
    MOVWF   PORTB
    BCF     PORTB, 7   ; Restore Keypad scan state
    BANKSEL INTCON
    BCF     INTCON, 1
    BSF     INTCON, 7  ; Re-enable Global Interrupts
    RETURN

PROCESS_KEY:
    BANKSEL KEY_VAL
    MOVF    KEY_VAL, W
    SUBLW   11         ; Key 'C' (Enter)
    BTFSC   STATUS, 2
    GOTO    KEY_ENTER
    MOVF    KEY_VAL, W
    SUBLW   10         ; Key 'B' (Decimal Point)
    BTFSC   STATUS, 2
    GOTO    KEY_DP
    MOVF    KEY_VAL, W
    SUBLW   12         ; Key 'D' (Cancel/NoOp)
    BTFSC   STATUS, 2
    RETURN
    GOTO    KEY_NUMBER
KEY_NUMBER:
    BANKSEL IS_FRAC_MODE
    BTFSC   IS_FRAC_MODE, 0
    GOTO    KEY_NUM_FRAC
    BANKSEL INPUT_ONES
    MOVF    INPUT_ONES, W
    BANKSEL INPUT_TENS
    MOVWF   INPUT_TENS      ; Shift Tens <- Ones
    BANKSEL KEY_VAL
    MOVF    KEY_VAL, W
    BANKSEL INPUT_ONES
    MOVWF   INPUT_ONES      ; New Ones
    RETURN
KEY_NUM_FRAC:
    BANKSEL FRAC_INDEX
    MOVF    FRAC_INDEX, W
    SUBLW   1
    BTFSS   STATUS, 0            
    RETURN                      
    BANKSEL FRAC_INDEX
    MOVF    FRAC_INDEX, W
    BTFSS   STATUS, 2            
    GOTO    FRAC_DIGIT_2
    BANKSEL KEY_VAL
    MOVF    KEY_VAL, W
    BANKSEL INPUT_TENTHS
    MOVWF   INPUT_TENTHS
    BANKSEL FRAC_INDEX
    INCF    FRAC_INDEX, F
    RETURN
FRAC_DIGIT_2:
    BANKSEL KEY_VAL
    MOVF    KEY_VAL, W
    BANKSEL INPUT_HUNDREDTHS
    MOVWF   INPUT_HUNDREDTHS
    BANKSEL FRAC_INDEX
    INCF    FRAC_INDEX, F
    RETURN
KEY_DP:
    BANKSEL IS_FRAC_MODE
    BSF     IS_FRAC_MODE, 0
    BANKSEL FRAC_INDEX
    CLRF    FRAC_INDEX
    RETURN
KEY_ENTER:
    BANKSEL INPUT_TENS
    MOVF    INPUT_TENS, W
    MOVWF   MATH_A_L
    CLRF    MATH_A_H
    MOVLW   10
    CALL    MULTIPLY_16x8   ; Convert inputs to binary
    BANKSEL RES_0
    MOVF    RES_0, W
    BANKSEL INPUT_ONES
    ADDWF   INPUT_ONES, W
    MOVWF   MATH_TEMP            
    MOVLW   10
    SUBWF   MATH_TEMP, W        
    BTFSS   STATUS, 0            
    GOTO    REJECT_VALUE        ; Min Limit Check
    MOVF    MATH_TEMP, W
    SUBLW   50                  
    BTFSS   STATUS, 0            
    GOTO    REJECT_VALUE        ; Max Limit Check
    MOVF    MATH_TEMP, W
    SUBLW   50
    BTFSS   STATUS, 2            
    GOTO    ACCEPT_VALUE        
    BANKSEL INPUT_TENTHS
    MOVF    INPUT_TENTHS, W
    BTFSS   STATUS, 2            
    GOTO    REJECT_VALUE        
ACCEPT_VALUE:
    MOVF    MATH_TEMP, W
    BANKSEL TARGET_TEMP_INT
    MOVWF   TARGET_TEMP_INT
    BANKSEL INPUT_TENTHS
    MOVF    INPUT_TENTHS, W
    MOVWF   MATH_A_L
    CLRF    MATH_A_H
    MOVLW   10
    CALL    MULTIPLY_16x8
    BANKSEL RES_0
    MOVF    RES_0, W
    BANKSEL INPUT_HUNDREDTHS
    ADDWF   INPUT_HUNDREDTHS, W
    BANKSEL TARGET_TEMP_FRAC
    MOVWF   TARGET_TEMP_FRAC
    BANKSEL INPUT_MODE
    BCF     INPUT_MODE, 0
    RETURN
REJECT_VALUE:
    BANKSEL INPUT_MODE
    BCF     INPUT_MODE, 0
    RETURN

DISPLAY_INPUT_BUFFER:
    BANKSEL INPUT_TENS
    MOVF    INPUT_TENS, W
    MOVWF   TENS_DIGIT
    SUBLW   0
    BTFSS   STATUS, 2 
    GOTO    CHECK_ONES
    MOVLW   10
    MOVWF   TENS_DIGIT      ; Blank if zero leading
CHECK_ONES:
    BANKSEL INPUT_ONES
    MOVF    INPUT_ONES, W
    MOVWF   ONES_DIGIT
    BANKSEL SHOW_DP
    BSF     SHOW_DP, 0
    BANKSEL INPUT_TENTHS
    MOVF    INPUT_TENTHS, W
    MOVWF   TENTHS_DIGIT
    BANKSEL INPUT_HUNDREDTHS
    MOVF    INPUT_HUNDREDTHS, W
    MOVWF   HUNDREDTHS_DIGIT
    RETURN

SCAN_KEYPAD:
    BANKSEL KEY_VAL
    MOVLW   255
    MOVWF   KEY_VAL
    BANKSEL PORTB
    ; Row 1
    BSF     PORTB, 5
    BSF     PORTB, 6
    BSF     PORTB, 7
    BCF     PORTB, 4
    CALL    KEYPAD_DELAY
    BTFSS   PORTB, 0 
    RETLW   1
    BTFSS   PORTB, 1 
    RETLW   4
    BTFSS   PORTB, 2 
    RETLW   7
    BTFSS   PORTB, 3 
    RETLW   10          ; Key '*'
    ; Row 2
    BANKSEL PORTB
    BSF     PORTB, 4
    BCF     PORTB, 5
    CALL    KEYPAD_DELAY
    BTFSS   PORTB, 0 
    RETLW   2
    BTFSS   PORTB, 1 
    RETLW   5
    BTFSS   PORTB, 2 
    RETLW   8
    BTFSS   PORTB, 3 
    RETLW   0           ; Key '0'
    ; Row 3
    BANKSEL PORTB
    BSF     PORTB, 5
    BCF     PORTB, 6
    CALL    KEYPAD_DELAY
    BTFSS   PORTB, 0 
    RETLW   3
    BTFSS   PORTB, 1 
    RETLW   6
    BTFSS   PORTB, 2 
    RETLW   9
    BTFSS   PORTB, 3 
    RETLW   11          ; Key '#'
    ; Row 4
    BANKSEL PORTB
    BSF     PORTB, 6
    BCF     PORTB, 7
    CALL    KEYPAD_DELAY
    BTFSS   PORTB, 0 
    RETLW   12          ; Key 'A' (mapped to IRQ)
    BTFSS   PORTB, 1 
    RETLW   13          ; Key 'B'
    BTFSS   PORTB, 2 
    RETLW   14          ; Key 'C'
    BTFSS   PORTB, 3 
    RETLW   15          ; Key 'D'
    MOVLW   255
    MOVWF   KEY_VAL
    RETURN

GET_DIGITS:
    CLRF    TENS_DIGIT
    MOVWF   MATH_A_L 
DIGIT_DIV_LOOP:
    MOVLW   10
    SUBWF   MATH_A_L, W
    BTFSS   STATUS, 0
    GOTO    DIGIT_DIV_DONE
    MOVWF   MATH_A_L
    INCF    TENS_DIGIT, F
    GOTO    DIGIT_DIV_LOOP
DIGIT_DIV_DONE:
    MOVF    MATH_A_L, W
    RETURN

;====================================================================
; DISPLAY ROUTINES (Multiplexing)
;====================================================================
DISPLAY_N_FRAMES:
    BANKSEL FRAME_COUNT
    MOVWF   FRAME_COUNT
FRAME_LOOP:
    CALL    DISPLAY_ONE_FRAME
    
    ; --- CHECK UART INSIDE DISPLAY LOOP ---
    CALL    CHECK_UART_FLAG ; Ensures UART responsiveness during display
    
    BANKSEL TEMP_CHECK_COUNT
    DECFSZ  TEMP_CHECK_COUNT, F
    GOTO    SKIP_TEMP_CHECK
    MOVLW   50
    MOVWF   TEMP_CHECK_COUNT
    CALL    READ_TEMPERATURE
    CALL    CONTROL_TEMP
SKIP_TEMP_CHECK:
    BANKSEL FRAME_COUNT
    DECFSZ  FRAME_COUNT, F
    GOTO    FRAME_LOOP
    RETURN

DISPLAY_ONE_FRAME:
    CALL    OFF_ALL
    ; Digit 1 (Tens)
    BANKSEL TENS_DIGIT
    MOVF    TENS_DIGIT, W
    CALL    GET_SEGMENT_CODE
    CALL    SEND_TO_PORTD
    BANKSEL PORTC
    MOVF    PORTC, W
    ANDLW   0xF0
    IORLW   0x01           
    MOVWF   PORTC
    CALL    SHORT_DELAY
    CALL    OFF_ALL
    ; Digit 2 (Ones)
    BANKSEL ONES_DIGIT
    MOVF    ONES_DIGIT, W
    CALL    GET_SEGMENT_CODE
    CALL    SEND_TO_PORTD
    BANKSEL SHOW_DP
    BTFSC   SHOW_DP, 0
    BSF     PORTD, 7      ; Turn on DP
    BANKSEL PORTC
    MOVF    PORTC, W
    ANDLW   0xF0
    IORLW   0x02           
    MOVWF   PORTC
    CALL    SHORT_DELAY
    CALL    OFF_ALL
    ; Digit 3 (Tenths)
    BANKSEL TENTHS_DIGIT
    MOVF    TENTHS_DIGIT, W
    CALL    GET_SEGMENT_CODE
    CALL    SEND_TO_PORTD
    BANKSEL PORTC
    MOVF    PORTC, W
    ANDLW   0xF0
    IORLW   0x04           
    MOVWF   PORTC
    CALL    SHORT_DELAY
    CALL    OFF_ALL
    ; Digit 4 (Hundredths)
    BANKSEL HUNDREDTHS_DIGIT
    MOVF    HUNDREDTHS_DIGIT, W
    CALL    GET_SEGMENT_CODE
    CALL    SEND_TO_PORTD
    BANKSEL PORTC
    MOVF    PORTC, W
    ANDLW   0xF0
    IORLW   0x08           
    MOVWF   PORTC
    CALL    SHORT_DELAY
    RETURN

OFF_ALL:
    BANKSEL PORTC
    MOVF    PORTC, W
    ANDLW   0xF0      ; Keep high nibble (Control pins), clear low (Common Anodes)
    MOVWF   PORTC
    BANKSEL PORTD
    CLRF    PORTD     ; Clear segments
    RETURN

SEND_TO_PORTD:
    BANKSEL TEMP_LOW
    MOVWF   TEMP_LOW
    MOVF    TEMP_LOW, W
    BANKSEL PORTD
    MOVWF   PORTD
    RETURN

GET_SEGMENT_CODE:
    BANKSEL TEMP_LOW
    MOVWF   TEMP_LOW
    MOVLW   HIGH(SEGMENT_TABLE)
    MOVWF   PCLATH
    MOVF    TEMP_LOW, W
    CALL    SEGMENT_TABLE
    RETURN

SEGMENT_TABLE:
    ADDWF   PCL, F
    RETLW   0x3F  ; 0
    RETLW   0x06  ; 1
    RETLW   0x5B  ; 2
    RETLW   0x4F  ; 3
    RETLW   0x66  ; 4
    RETLW   0x6D  ; 5
    RETLW   0x7D  ; 6
    RETLW   0x07  ; 7
    RETLW   0x7F  ; 8
    RETLW   0x6F  ; 9
    RETLW   0x00  ; 10 (Blank)

SHORT_DELAY:
    BANKSEL DELAY_COUNT
    MOVLW   0xFF
    MOVWF   DELAY_COUNT
SHORT_DELAY_LOOP:
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    DECFSZ  DELAY_COUNT, F
    GOTO    SHORT_DELAY_LOOP
    RETURN

KEYPAD_DELAY:
    BANKSEL DELAY_COUNT
    MOVLW   0x80 
    MOVWF   DELAY_COUNT
KEYPAD_DELAY_LOOP:
    NOP
    NOP
    NOP
    NOP
    DECFSZ  DELAY_COUNT, F
    GOTO    KEYPAD_DELAY_LOOP
    RETURN

DELAY:
    BANKSEL DELAY_COUNT
    MOVLW   0x32
    MOVWF   DELAY_COUNT
DELAY_OUTER:
    MOVLW   0xFF
    MOVWF   DELAY_COUNT2
DELAY_INNER:
    DECFSZ  DELAY_COUNT2, F
    GOTO    DELAY_INNER
    DECFSZ  DELAY_COUNT, F
    GOTO    DELAY_OUTER
    RETURN

; ==============================================================================
; UART ROUTINES (Updated & Full Logic)
; ==============================================================================

CHECK_UART_FLAG:
    BANKSEL UART_READY
    BTFSS   UART_READY, 0   ; Data Ready?
    RETURN                  ; No
    
    BCF     UART_READY, 0   ; Clear Flag
    GOTO    PROCESS_UART_DATA

PROCESS_UART_DATA:
    BANKSEL UART_DATA
    MOVF    UART_DATA, W
    MOVWF   UART_TEMP_REG
    
    ; Check SET (Bit 7=1) or GET (Bit 7=0)
    BTFSC   UART_TEMP_REG, 7
    GOTO    UART_SET_CMD
    GOTO    UART_GET_CMD

UART_GET_CMD:
    MOVF    UART_TEMP_REG, W
    SUBLW   0x01
    BTFSC   STATUS, 2
    GOTO    UART_GET_DESIRED_FRAC
    
    MOVF    UART_TEMP_REG, W
    SUBLW   0x02
    BTFSC   STATUS, 2
    GOTO    UART_GET_DESIRED_INT
    
    MOVF    UART_TEMP_REG, W
    SUBLW   0x03
    BTFSC   STATUS, 2
    GOTO    UART_GET_AMBIENT_FRAC
    
    MOVF    UART_TEMP_REG, W
    SUBLW   0x04
    BTFSC   STATUS, 2
    GOTO    UART_GET_AMBIENT_INT
    
    MOVF    UART_TEMP_REG, W
    SUBLW   0x05
    BTFSC   STATUS, 2
    GOTO    UART_GET_FAN_SPEED
    
    RETURN

UART_GET_DESIRED_FRAC:
    BANKSEL TARGET_TEMP_FRAC
    MOVF    TARGET_TEMP_FRAC, W
    CALL    UART_SEND
    RETURN

UART_GET_DESIRED_INT:
    BANKSEL TARGET_TEMP_INT
    MOVF    TARGET_TEMP_INT, W
    CALL    UART_SEND
    RETURN

UART_GET_AMBIENT_FRAC:
    BANKSEL FRAC_TEMP
    MOVF    FRAC_TEMP, W
    CALL    UART_SEND
    RETURN

UART_GET_AMBIENT_INT:
    BANKSEL AMBIENT_TEMP
    MOVF    AMBIENT_TEMP, W
    CALL    UART_SEND
    RETURN

UART_GET_FAN_SPEED:
    BANKSEL FAN_SPEED_STORE
    MOVF    FAN_SPEED_STORE, W
    CALL    UART_SEND
    RETURN

UART_SET_CMD:
    ; Bit 6: 0=Frac, 1=Int
    BANKSEL UART_TEMP_REG
    BTFSC   UART_TEMP_REG, 6
    GOTO    UART_SET_DESIRED_INT
    
    ; Set Frac (10xxxxxx)
    MOVF    UART_TEMP_REG, W
    ANDLW   0x3F
    BANKSEL TARGET_TEMP_FRAC
    MOVWF   TARGET_TEMP_FRAC
    RETURN

UART_SET_DESIRED_INT:
    ; Set Int (11xxxxxx)
    BANKSEL UART_TEMP_REG
    MOVF    UART_TEMP_REG, W
    ANDLW   0x3F
    BANKSEL TARGET_TEMP_INT
    MOVWF   TARGET_TEMP_INT
    RETURN

UART_SEND:
    BANKSEL UART_DATA
    MOVWF   UART_DATA        
UART_WAIT_TX:
    BANKSEL TXSTA
    BTFSS   TXSTA, 1        ; TRMT (Transmit Shift Register Status) - Buffer Empty?
    GOTO    UART_WAIT_TX
    
    BANKSEL UART_DATA
    MOVF    UART_DATA, W
    BANKSEL TXREG
    MOVWF   TXREG           ; Write data to Send
    RETURN

; ==============================================================================
; END OF CODE
; ==============================================================================
END