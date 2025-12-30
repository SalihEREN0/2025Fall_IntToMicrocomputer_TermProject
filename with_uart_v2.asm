;====================================================================
; BOARD 1: HOME AIR CONDITIONER SYSTEM (FULL VERSION)
; Requirements: [R2.1.1], [R2.1.2], [R2.1.3], [R2.1.4]
; Protocol: [Source 197]
;====================================================================
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
#define HEATER_PIN 4     ; RC4
#define COOLER_PIN 5     ; RC5

;====================================================================
; VARIABLES
;====================================================================
PSECT udata_bank0
    ; Core System Data
    TARGET_TEMP_INT:   DS 1   ; [R2.1.1-1] Desired Temp Integer
    TARGET_TEMP_FRAC:  DS 1   ; [R2.1.1-1] Desired Temp Fraction
    AMBIENT_TEMP:      DS 1   ; [R2.1.1-4] Ambient Temp Integer
    FRAC_TEMP:         DS 1   ; Ambient Temp Fraction
    FAN_SPEED_STORE:   DS 1   ; [R2.1.1-5] Fan Speed

    ; Display & Logic Variables
    VAL_INT:           DS 1
    VAL_FRAC:          DS 1
    TEMP_LOW:          DS 1
    DELAY_COUNT:       DS 1
    DELAY_COUNT2:      DS 1
    TENS_DIGIT:        DS 1
    ONES_DIGIT:        DS 1
    TENTHS_DIGIT:      DS 1
    HUNDREDTHS_DIGIT:  DS 1
    FRAME_COUNT:       DS 1
    TEMP_CHECK_COUNT:  DS 1
    SHOW_DP:           DS 1

    ; Keypad Input Variables
    INPUT_MODE:        DS 1
    KEY_VAL:           DS 1
    INPUT_TENS:        DS 1
    INPUT_ONES:        DS 1
    INPUT_TENTHS:      DS 1
    INPUT_HUNDREDTHS:  DS 1
    IS_FRAC_MODE:      DS 1
    FRAC_INDEX:        DS 1
    LAST_KEY:          DS 1
    
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
    UART_DATA:         DS 1   ; Received Data Buffer
    UART_READY:        DS 1   ; Flag: 1=Data Ready, 0=Empty
    UART_TEMP_REG:     DS 1   ; Temp var for ISR

    ; Interrupt Context
    W_TEMP:            DS 1
    STATUS_TEMP:       DS 1
    PCLATH_TEMP:       DS 1

;====================================================================
; VECTORS
;====================================================================
PSECT resetVec,class=CODE,delta=2
    GOTO MAIN

PSECT intVec,class=CODE,delta=2,abs
ORG 0x0004
    GOTO ISR

;====================================================================
; ISR (INTERRUPT SERVICE ROUTINE)
;====================================================================
PSECT code
ISR:
    ; Context Save
    MOVWF   W_TEMP
    SWAPF   STATUS, W
    MOVWF   STATUS_TEMP
    CLRF    STATUS
    MOVF    PCLATH, W
    MOVWF   PCLATH_TEMP
    CLRF    PCLATH

    ; --- 1. UART RX INTERRUPT CHECK ---
    BANKSEL PIR1
    BTFSS   PIR1, 5         ; RCIF Set?
    GOTO    CHECK_EXT_INT   ; No, check RB0

    ; Check Overrun Error
    BANKSEL RCSTA
    BTFSC   RCSTA, 1        ; OERR Set?
    GOTO    UART_OERR_RESET

    ; Read Data
    BANKSEL RCREG
    MOVF    RCREG, W        ; Read RCREG clears RCIF
    BANKSEL UART_DATA
    MOVWF   UART_DATA       ; Store in RAM
    MOVLW   1
    MOVWF   UART_READY      ; Set Flag
    GOTO    CHECK_EXT_INT

UART_OERR_RESET:
    BCF     RCSTA, 4        ; CREN = 0
    BSF     RCSTA, 4        ; CREN = 1
    GOTO    CHECK_EXT_INT

    ; --- 2. EXTERNAL INTERRUPT (RB0) CHECK ---
CHECK_EXT_INT:
    BANKSEL INTCON
    BTFSS   INTCON, 1       ; INTF Set?
    GOTO    ISR_EXIT

    ; Handle 'A' Button Press logic
    BANKSEL INPUT_MODE
    BSF     INPUT_MODE, 0
    BANKSEL INTCON
    BCF     INTCON, 1       ; Clear INTF

ISR_EXIT:
    ; Context Restore
    MOVF    PCLATH_TEMP, W
    MOVWF   PCLATH
    SWAPF   STATUS_TEMP, W
    MOVWF   STATUS
    SWAPF   W_TEMP, F
    SWAPF   W_TEMP, W
    RETFIE

;====================================================================
; MAIN PROGRAM
;====================================================================
MAIN:
    CALL    DELAY
    CALL    DELAY
    BANKSEL INTCON
    CLRF    INTCON 
    CALL    INIT_SYSTEM

MAIN_LOOP:
    ; 1. Check Keypad Input Mode
    BANKSEL INPUT_MODE
    BTFSC   INPUT_MODE, 0
    CALL    HANDLE_INPUT_MODE

    ; 2. Check UART Commands
    CALL    CHECK_UART_FLAG

    ; 3. Ambient Temperature Handling
    CALL    READ_TEMPERATURE
    CALL    CONTROL_TEMP
    
    BANKSEL AMBIENT_TEMP
    MOVF    AMBIENT_TEMP, W
    MOVWF   VAL_INT
    MOVF    FRAC_TEMP, W
    MOVWF   VAL_FRAC
    CALL    CONVERT_TO_DIGITS
    
    MOVLW   45
    CALL    DISPLAY_N_FRAMES ; Shows Ambient
    
    BANKSEL INPUT_MODE
    BTFSC   INPUT_MODE, 0
    GOTO    MAIN_LOOP 
    
    MOVLW   45
    CALL    DISPLAY_N_FRAMES
    
    ; 4. Target Temperature Handling
    BANKSEL TARGET_TEMP_INT
    MOVF    TARGET_TEMP_INT, W
    MOVWF   VAL_INT
    MOVF    TARGET_TEMP_FRAC, W
    MOVWF   VAL_FRAC
    CALL    CONVERT_TO_DIGITS
    
    MOVLW   45
    CALL    DISPLAY_N_FRAMES ; Shows Target
    MOVLW   45
    CALL    DISPLAY_N_FRAMES
    
    ; 5. Fan Speed Handling (RPS)
    BANKSEL SHOW_DP
    CLRF    SHOW_DP          ; RPS is integer, hide DP
    
    BANKSEL TMR0
    MOVF    TMR0, W          ; Use TMR0 for simulation value
    MOVWF   MATH_TEMP
    BCF     STATUS, 0
    RRF     MATH_TEMP, F     ; Scale it
    
    MOVF    MATH_TEMP, W
    BANKSEL FAN_SPEED_STORE
    MOVWF   FAN_SPEED_STORE  ; Store for UART
    
    CALL    CONVERT_RPS_TO_DIGITS
    
    MOVLW   45
    CALL    DISPLAY_N_FRAMES ; Shows Fan Speed
    MOVLW   45
    CALL    DISPLAY_N_FRAMES
    
    BANKSEL SHOW_DP
    MOVLW   1
    MOVWF   SHOW_DP          ; Restore DP
    
    GOTO    MAIN_LOOP

;====================================================================
; SYSTEM INITIALIZATION
;====================================================================
INIT_SYSTEM:
    BANKSEL TRISA
    MOVLW   0xFF        ; Port A Inputs
    MOVWF   TRISA
    
    MOVLW   0x0F        ; Port B: RB0-3 Input, RB4-7 Output (Keypad)
    MOVWF   TRISB
    
    MOVLW   0x80        ; RC7(RX)=Input, RC6(TX)=Output
    MOVWF   TRISC
    
    CLRF    TRISD       ; Port D Output (Segments)
    
    MOVLW   0x8E        ; ADCON1 (AN0 Analog)
    MOVWF   ADCON1
    
    MOVLW   0x28        ; OPTION_REG (TMR0 Setup)
    MOVWF   OPTION_REG
    
    BANKSEL PORTA
    CLRF    PORTA
    CLRF    PORTB
    CLRF    PORTC
    CLRF    PORTD
    CLRF    AMBIENT_TEMP
    CLRF    FAN_SPEED_STORE
    CLRF    INPUT_MODE
    CLRF    UART_READY
    
    BANKSEL TARGET_TEMP_INT
    MOVLW   27
    MOVWF   TARGET_TEMP_INT
    CLRF    TARGET_TEMP_FRAC
    
    BANKSEL SHOW_DP
    MOVLW   1
    MOVWF   SHOW_DP
    
    BANKSEL TEMP_CHECK_COUNT
    MOVLW   50
    MOVWF   TEMP_CHECK_COUNT
    
    MOVLW   0x81        ; ADCON0
    MOVWF   ADCON0
    
    ; --- UART CONFIG (9600 Baud) ---
    BANKSEL SPBRG
    MOVLW   25          ; 4MHz assumed
    MOVWF   SPBRG
    
    BANKSEL TXSTA
    MOVLW   0x24        ; TXEN=1, BRGH=1
    MOVWF   TXSTA
    
    BANKSEL RCSTA
    MOVLW   0x90        ; SPEN=1, CREN=1
    MOVWF   RCSTA
    
    ; Clear Buffer
    BANKSEL RCREG
    MOVF    RCREG, W
    MOVF    RCREG, W
    
    ; Keypad Init Port B
    BANKSEL PORTB
    MOVLW   0xF0
    MOVWF   PORTB
    BCF     PORTB, 7
    
    ; --- INTERRUPT ENABLES ---
    BANKSEL PIE1
    BSF     PIE1, 5     ; RCIE (UART RX)
    
    BANKSEL INTCON
    BSF     INTCON, 4   ; INTE (RB0)
    BSF     INTCON, 6   ; PEIE
    BSF     INTCON, 7   ; GIE
    
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
    BSF     ADCON0, 2
WAIT_ADC:
    BTFSC   ADCON0, 2
    GOTO    WAIT_ADC
    BANKSEL ADRESL
    MOVF    ADRESL, W
    BANKSEL MATH_A_L
    MOVWF   MATH_A_L
    BANKSEL ADRESH
    MOVF    ADRESH, W
    BANKSEL MATH_A_H
    MOVWF   MATH_A_H
    MOVLW   244
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
    MOVWF   DIVISOR_H
    CALL    DIVIDE_24x16
    BANKSEL RES_0
    MOVF    RES_0, W
    BANKSEL AMBIENT_TEMP
    MOVWF   AMBIENT_TEMP
    BANKSEL REM_0
    MOVF    REM_0, W
    BANKSEL MATH_A_L
    MOVWF   MATH_A_L
    BANKSEL REM_1
    MOVF    REM_1, W
    BANKSEL MATH_A_H
    MOVWF   MATH_A_H
    MOVLW   100
    CALL    MULTIPLY_16x8
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
    MOVWF   FRAC_TEMP
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
    BTFSC   STATUS, 2         
    GOTO    CHECK_FRACTION     
    BTFSS   STATUS, 0         
    GOTO    TOO_HOT             
    GOTO    TOO_COLD
CHECK_FRACTION:
    BANKSEL FRAC_TEMP
    MOVF    FRAC_TEMP, W
    BANKSEL TARGET_TEMP_FRAC
    SUBWF   TARGET_TEMP_FRAC, W 
    BTFSC   STATUS, 2         
    GOTO    TEMP_OK
    BTFSS   STATUS, 0         
    GOTO    TOO_HOT
    GOTO    TOO_COLD
TOO_COLD:
    BANKSEL PORTC
    BSF     PORTC, HEATER_PIN
    BCF     PORTC, COOLER_PIN
    RETURN
TOO_HOT:
    BANKSEL PORTC
    BCF     PORTC, HEATER_PIN
    BSF     PORTC, COOLER_PIN
    RETURN
TEMP_OK:
    BANKSEL PORTC
    BCF     PORTC, HEATER_PIN
    BCF     PORTC, COOLER_PIN
    RETURN

CONVERT_TO_DIGITS:
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
    BCF     INTCON, 7 
    BANKSEL PORTC
    BCF     PORTC, 4 
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
    CALL    DISPLAY_INPUT_BUFFER
    CALL    DISPLAY_ONE_FRAME
    CALL    SCAN_KEYPAD
    BANKSEL KEY_VAL
    MOVWF   KEY_VAL
    BANKSEL KEY_VAL
    MOVF    KEY_VAL, W
    BANKSEL LAST_KEY
    XORWF   LAST_KEY, W
    BTFSC   STATUS, 2 
    GOTO    INPUT_LOOP_CONTINUE 
    BANKSEL KEY_VAL
    MOVF    KEY_VAL, W
    BANKSEL LAST_KEY
    MOVWF   LAST_KEY
    SUBLW   255
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
    BTFSS   STATUS, 2           
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
    BCF     PORTB, 7
    BANKSEL INTCON
    BCF     INTCON, 1
    BSF     INTCON, 7 
    RETURN

PROCESS_KEY:
    BANKSEL KEY_VAL
    MOVF    KEY_VAL, W
    SUBLW   11
    BTFSC   STATUS, 2
    GOTO    KEY_ENTER
    MOVF    KEY_VAL, W
    SUBLW   10
    BTFSC   STATUS, 2
    GOTO    KEY_DP
    MOVF    KEY_VAL, W
    SUBLW   12
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
    MOVWF   INPUT_TENS
    BANKSEL KEY_VAL
    MOVF    KEY_VAL, W
    BANKSEL INPUT_ONES
    MOVWF   INPUT_ONES
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
    CALL    MULTIPLY_16x8
    BANKSEL RES_0
    MOVF    RES_0, W
    BANKSEL INPUT_ONES
    ADDWF   INPUT_ONES, W
    MOVWF   MATH_TEMP           
    MOVLW   10
    SUBWF   MATH_TEMP, W        
    BTFSS   STATUS, 0           
    GOTO    REJECT_VALUE        
    MOVF    MATH_TEMP, W
    SUBLW   50                  
    BTFSS   STATUS, 0           
    GOTO    REJECT_VALUE        
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
    MOVWF   TENS_DIGIT
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
    RETLW   10
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
    RETLW   0
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
    RETLW   11
    BANKSEL PORTB
    BSF     PORTB, 6
    BCF     PORTB, 7
    CALL    KEYPAD_DELAY
    BTFSS   PORTB, 0 
    RETLW   12
    BTFSS   PORTB, 1 
    RETLW   13
    BTFSS   PORTB, 2 
    RETLW   14
    BTFSS   PORTB, 3 
    RETLW   15
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
; DISPLAY ROUTINES
;====================================================================
DISPLAY_N_FRAMES:
    BANKSEL FRAME_COUNT
    MOVWF   FRAME_COUNT
FRAME_LOOP:
    CALL    DISPLAY_ONE_FRAME
    
    ; --- CHECK UART INSIDE DISPLAY LOOP ---
    CALL    CHECK_UART_FLAG
    
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
    BANKSEL ONES_DIGIT
    MOVF    ONES_DIGIT, W
    CALL    GET_SEGMENT_CODE
    CALL    SEND_TO_PORTD
    BANKSEL SHOW_DP
    BTFSC   SHOW_DP, 0
    BSF     PORTD, 7
    BANKSEL PORTC
    MOVF    PORTC, W
    ANDLW   0xF0
    IORLW   0x02          
    MOVWF   PORTC
    CALL    SHORT_DELAY
    CALL    OFF_ALL
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
    ANDLW   0xF0      
    MOVWF   PORTC
    BANKSEL PORTD
    CLRF    PORTD
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
    BTFSS   TXSTA, 1        ; TRMT (Buffer Empty?)
    GOTO    UART_WAIT_TX
    
    BANKSEL UART_DATA
    MOVF    UART_DATA, W
    BANKSEL TXREG
    MOVWF   TXREG           
    RETURN

; ==============================================================================
; END OF CODE
; ==============================================================================
END