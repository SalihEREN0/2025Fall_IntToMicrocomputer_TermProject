

    LIST P=16F877A
    INCLUDE "P16F877A.INC"

    __CONFIG _FOSC_XT & _WDTE_OFF & _PWRTE_ON & _BOREN_OFF & _LVP_OFF & _CPD_OFF & _WRT_OFF & _CP_OFF

    ERRORLEVEL -302


    CBLOCK 0x20
        DLY_V1, DLY_V2, DLY_LOOP
        LCD_REG, NUM_H, NUM_T, NUM_O
        VAL_POT, VAL_LDR, ADC_CH_TEMP
        PERC_TARGET, PERC_CURRENT
        MOTOR_IDX, STEP_LOOP_CTR
        
        IS_AUTO            
        UART_DATA           
        TEMP_TX             
    ENDC


#DEFINE LCD_RS   PORTD, 2
#DEFINE LCD_E    PORTD, 3
#DEFINE LCD_RW   PORTD, 0
#DEFINE LDR_LIMIT  d'100'

    ORG 0x000
    GOTO MAIN_SETUP


MAIN_SETUP:
    BANKSEL TRISA
    MOVLW   B'00000011'     
    MOVWF   TRISA
    CLRF    TRISB          
    CLRF    TRISD           
    
    
    BANKSEL TRISC
    BCF     TRISC, 6       
    BSF     TRISC, 7       
    
    MOVLW   d'25'           
    MOVWF   SPBRG
    MOVLW   B'00100100'     
    MOVWF   TXSTA
    BANKSEL RCSTA
    MOVLW   B'10010000'     
    MOVWF   RCSTA
    
   
    BANKSEL ADCON1
    MOVLW   B'00000100'     
    MOVWF   ADCON1
    
    
    BANKSEL PORTA
    CLRF    PORTA
    CLRF    PORTB
    CLRF    PORTD
    CLRF    PERC_CURRENT
    
    
    CALL    LCD_INIT
    CALL    LCD_CLEAR
    
  
    CALL    DELAY_500MS


MAIN_LOOP:
    
    CALL    CHECK_UART_PDF
    
   
    MOVLW   d'0'
    CALL    READ_ADC
    MOVWF   VAL_LDR
    MOVLW   d'1'
    CALL    READ_ADC
    MOVWF   VAL_POT

   
    MOVF    IS_AUTO, W
    SUBLW   d'2'           
    BTFSC   STATUS, Z
    GOTO    MOVE_MOTOR     
    
    
    MOVLW   LDR_LIMIT
    SUBWF   VAL_LDR, W      
    BTFSC   STATUS, C       
    GOTO    MODE_AUTO       
    
    
    MOVLW   d'0'
    MOVWF   IS_AUTO
    BCF     STATUS, C
    RRF     VAL_POT, W      
    MOVWF   PERC_TARGET
    MOVLW   d'100'
    SUBWF   PERC_TARGET, W
    BTFSS   STATUS, C       
    GOTO    MOVE_MOTOR      
    MOVLW   d'100'          
    MOVWF   PERC_TARGET
    GOTO    MOVE_MOTOR

MODE_AUTO:
    MOVLW   d'1'
    MOVWF   IS_AUTO
    MOVLW   d'100'
    MOVWF   PERC_TARGET

    
MOVE_MOTOR:
    MOVF    PERC_TARGET, W
    SUBWF   PERC_CURRENT, W
    BTFSC   STATUS, Z       
    GOTO    UPDATE_SCREEN   
    
    MOVF    PERC_CURRENT, W
    SUBWF   PERC_TARGET, W
    BTFSS   STATUS, C       
    GOTO    GO_OPEN         
    GOTO    GO_CLOSE        

GO_CLOSE:
    CALL    MOVE_1_PERCENT_CCW
    INCF    PERC_CURRENT, F
    GOTO    MOVE_MOTOR      

GO_OPEN:
    CALL    MOVE_1_PERCENT_CW
    DECF    PERC_CURRENT, F
    GOTO    MOVE_MOTOR      

    
UPDATE_SCREEN:
    MOVLW   0x80
    CALL    LCD_CMD
   
    MOVLW   '+'
    CALL    LCD_CHAR
    MOVLW   '2'
    CALL    LCD_CHAR
    MOVLW   '5'
    CALL    LCD_CHAR
    MOVLW   '.'
    CALL    LCD_CHAR
    MOVLW   '0'
    CALL    LCD_CHAR
    MOVLW   0xDF
    CALL    LCD_CHAR
    MOVLW   'C'
    CALL    LCD_CHAR
    MOVLW   ' '
    CALL    LCD_CHAR
    MOVLW   '1'
    CALL    LCD_CHAR
    MOVLW   '0'
    CALL    LCD_CHAR
    MOVLW   '1'
    CALL    LCD_CHAR
    MOVLW   '3'
    CALL    LCD_CHAR
    MOVLW   'h'
    CALL    LCD_CHAR
    MOVLW   'P'
    CALL    LCD_CHAR
    MOVLW   'a'
    CALL    LCD_CHAR

    MOVLW   0xC0
    CALL    LCD_CMD
    
    MOVF    PERC_CURRENT, W
    CALL    BCD_CONVERT
    CALL    BCD_PRINT
    MOVLW   '%'
    CALL    LCD_CHAR
    MOVLW   ' '
    CALL    LCD_CHAR
    
    
    MOVLW   '0'
    CALL    LCD_CHAR
    MOVF    VAL_LDR, W
    CALL    BCD_CONVERT
    CALL    BCD_PRINT
    MOVLW   ' '
    CALL    LCD_CHAR
    MOVLW   'L'
    CALL    LCD_CHAR
    MOVLW   'u'
    CALL    LCD_CHAR
    MOVLW   'x'
    CALL    LCD_CHAR
    
    CALL    DELAY_200MS
    GOTO    MAIN_LOOP


CHECK_UART_PDF:
   
    BANKSEL RCSTA
    BTFSC   RCSTA, OERR
    GOTO    UART_ERR
    BTFSC   RCSTA, FERR
    GOTO    UART_ERR
    
    
    BANKSEL PIR1
    BTFSS   PIR1, RCIF
    RETURN             
    
    
    BANKSEL RCREG
    MOVF    RCREG, W
    MOVWF   UART_DATA
    BANKSEL PORTA
    
    
    
    
    MOVF    UART_DATA, W
    SUBLW   0x02
    BTFSC   STATUS, Z
    GOTO    CMD_SEND_CURTAIN
    
    
    MOVF    UART_DATA, W
    SUBLW   0x08
    BTFSC   STATUS, Z
    GOTO    CMD_SEND_LIGHT
    
    
    MOVF    UART_DATA, W
    ANDLW   B'11000000'     ; Ust 2 bite bak
    SUBLW   B'11000000'     ; 11 mi?
    BTFSC   STATUS, Z
    GOTO    CMD_SET_CURTAIN
    
    RETURN

CMD_SEND_CURTAIN:
   
    MOVF    PERC_CURRENT, W
    CALL    UART_TX
    RETURN

CMD_SEND_LIGHT:
   
    MOVF    VAL_LDR, W
    CALL    UART_TX
    RETURN

CMD_SET_CURTAIN:
   
    
    MOVF    UART_DATA, W
    ANDLW   B'00111111'     
    MOVWF   PERC_TARGET
    
    
    MOVLW   d'2'
    MOVWF   IS_AUTO
    RETURN

UART_ERR:
    
    BCF     RCSTA, CREN
    MOVF    RCREG, W
    BSF     RCSTA, CREN
    BANKSEL PORTA
    RETURN

UART_TX:
    MOVWF   TEMP_TX
    BANKSEL TXSTA
WT_TX:
    BTFSS   TXSTA, TRMT     
    GOTO    WT_TX
    BANKSEL TXREG
    MOVF    TEMP_TX, W
    MOVWF   TXREG
    BANKSEL PORTA
    RETURN


BCD_CONVERT:
    CLRF    NUM_H
    CLRF    NUM_T
    CLRF    NUM_O
    MOVWF   NUM_O
C_H:MOVLW   d'100'
    SUBWF   NUM_O, W
    BTFSS   STATUS, C
    GOTO    C_T
    MOVWF   NUM_O
    INCF    NUM_H, F
    GOTO    C_H
C_T:MOVLW   d'10'
    SUBWF   NUM_O, W
    BTFSS   STATUS, C
    GOTO    C_E
    MOVWF   NUM_O
    INCF    NUM_T, F
    GOTO    C_T
C_E:RETURN

BCD_PRINT:
    MOVF    NUM_H, W
    ADDLW   '0'
    CALL    LCD_CHAR
    MOVF    NUM_T, W
    ADDLW   '0'
    CALL    LCD_CHAR
    MOVF    NUM_O, W
    ADDLW   '0'
    CALL    LCD_CHAR
    RETURN

MOVE_1_PERCENT_CCW:
    MOVLW   d'10'           
    MOVWF   STEP_LOOP_CTR
CCW_LOOP:
    INCF    MOTOR_IDX, F    
    CALL    DO_PHYSICAL_STEP
    DECFSZ  STEP_LOOP_CTR, F
    GOTO    CCW_LOOP
    RETURN

MOVE_1_PERCENT_CW:
    MOVLW   d'10'           
    MOVWF   STEP_LOOP_CTR
CW_LOOP:
    DECF    MOTOR_IDX, F    
    CALL    DO_PHYSICAL_STEP
    DECFSZ  STEP_LOOP_CTR, F
    GOTO    CW_LOOP
    RETURN

DO_PHYSICAL_STEP:
    MOVLW   B'00000011'     
    ANDWF   MOTOR_IDX, F
    MOVF    MOTOR_IDX, W
    CALL    GET_STEP_TABLE
    MOVWF   PORTB           
    CALL    DELAY_MOTOR     
    RETURN

GET_STEP_TABLE:
    ADDWF   PCL, F
    RETLW   B'00000011'
    RETLW   B'00000110'
    RETLW   B'00001100'
    RETLW   B'00001001'

READ_ADC:
    MOVWF   ADC_CH_TEMP
    MOVLW   B'01000001'     
    MOVWF   ADCON0
    BTFSC   ADC_CH_TEMP, 0  
    BSF     ADCON0, 3       
    CALL    DELAY_TINY
    BSF     ADCON0, 2       
ADC_WAIT:
    BTFSC   ADCON0, 2
    GOTO    ADC_WAIT
    MOVF    ADRESH, W       
    RETURN

LCD_INIT:
    MOVLW   d'200'
    MOVWF   DLY_V1
LP_I1:  MOVLW   d'250'
    MOVWF   DLY_V2
LP_I2:  DECFSZ  DLY_V2, F
    GOTO    LP_I2
    DECFSZ  DLY_V1, F
    GOTO    LP_I1
    BCF     LCD_RW          
    MOVLW   0x03
    CALL    LCD_NIB
    CALL    DELAY_5MS
    MOVLW   0x03
    CALL    LCD_NIB
    CALL    DELAY_5MS
    MOVLW   0x03
    CALL    LCD_NIB
    CALL    DELAY_5MS
    MOVLW   0x02
    CALL    LCD_NIB
    CALL    DELAY_5MS
    MOVLW   0x28
    CALL    LCD_CMD
    MOVLW   0x0C
    CALL    LCD_CMD
    MOVLW   0x06
    CALL    LCD_CMD
    MOVLW   0x01
    CALL    LCD_CMD
    CALL    DELAY_5MS
    RETURN

LCD_CHAR:
    BSF     LCD_RS
    GOTO    LCD_W
LCD_CMD:
    BCF     LCD_RS
LCD_W:
    MOVWF   LCD_REG
    SWAPF   LCD_REG, W
    ANDLW   0x0F
    CALL    LCD_NIB
    MOVF    LCD_REG, W
    ANDLW   0x0F
    CALL    LCD_NIB
    CALL    DELAY_TINY
    RETURN

LCD_NIB:
    MOVWF   DLY_V1
    SWAPF   DLY_V1, F       
    MOVF    DLY_V1, W
    ANDLW   0xF0            
    MOVWF   DLY_V1
    MOVF    PORTD, W
    ANDLW   0x0F            
    IORWF   DLY_V1, W       
    MOVWF   PORTD           
    NOP
    BSF     LCD_E           
    CALL    DELAY_TINY      
    BCF     LCD_E           
    RETURN

LCD_CLEAR:
    MOVLW   0x01
    CALL    LCD_CMD
    CALL    DELAY_5MS
    RETURN

DELAY_MOTOR:
    MOVLW   d'15'           
    MOVWF   DLY_V1
D_M:MOVLW   d'50'
    MOVWF   DLY_V2
D_M2:DECFSZ DLY_V2, F
    GOTO    D_M2
    DECFSZ  DLY_V1, F
    GOTO    D_M
    RETURN

DELAY_500MS:
    MOVLW   d'10'
    MOVWF   DLY_LOOP
D500:CALL   DELAY_50MS
    DECFSZ  DLY_LOOP, F
    GOTO    D500
    RETURN

DELAY_200MS:
    MOVLW   d'4'
    MOVWF   DLY_LOOP
D200:CALL   DELAY_50MS
    DECFSZ  DLY_LOOP, F
    GOTO    D200
    RETURN

DELAY_50MS:
    MOVLW   d'100'
    MOVWF   DLY_V1
DL1:MOVLW   d'160'
    MOVWF   DLY_V2
DL2:DECFSZ  DLY_V2, F
    GOTO    DL2
    DECFSZ  DLY_V1, F
    GOTO    DL1
    RETURN

DELAY_5MS:
    MOVLW   d'20'           
    MOVWF   DLY_V1
DL3:MOVLW   d'160'
    MOVWF   DLY_V2
DL4:DECFSZ  DLY_V2, F
    GOTO    DL4
    DECFSZ  DLY_V1, F
    GOTO    DL3
    RETURN

DELAY_TINY:
    MOVLW   d'50'           
    MOVWF   DLY_V1
D_TINY_LP:
    DECFSZ  DLY_V1, F
    GOTO    D_TINY_LP
    RETURN

    END