;
;;=======================================================================================
;; The collection of input/output related functions starts here
;;=======================================================================================
;
; Define io system specific constants and memory areas etc. It is expected that the
; basic definitions from sysdef.asm have been included somewhere before!
;
;***************************************************************************************
;* IO$DUMP_MEMORY prints a hexadecimal memory dump of a specified memory region.
;*
;* R8:  Contains the start address
;* R9:  Contains the end address (inclusive)
;*
;* The contents of R8 and R9 are preserved during the run of this function.
;***************************************************************************************
;
IO$DUMP_MEMORY          INCRB                           ; Get a new register page
                        MOVE R8, R0                     ; R0 will be the loop counter
                        MOVE R8, R1                     ; This will be needed to restore R8 later
                        MOVE R9, R3
                        ADD 0x0001, R3                  ; That is necessary since we want the last 
                                                        ; address printed, too
                        MOVE 0xFFFF, R4                 ; Set R4 - this is the column counter - to -1
_IO$DUMP_MEMORY_LOOP    CMP R3, R0                      ; Have we reached the end of the memory area?
                        RBRA _IO$DUMP_MEMORY_EXIT, !N   ; Yes - that is it, so exit this routine
                        ADD 0x0001, R4                  ; Next column
                        AND 0x0007, R4                  ; We compute mod 8
                        RBRA _IO$DUMP_MEMORY_CONTENT, !Z; if the result is not equal 0 we do not 
                                                        ; need an address printed
                        RSUB IO$PUT_CRLF, 1             ; Print a CR/LF pair
                        MOVE R0, R8                     ; Print address
                        RSUB IO$PUT_W_HEX, 1
                        MOVE IO$COLON_DELIMITER, R8     ; Print a colon followed by a space
                        RSUB IO$PUTS, 1
_IO$DUMP_MEMORY_CONTENT MOVE @R0++, R8                  ; Print the memory contents of this location
                        RSUB IO$PUT_W_HEX, 1
                        MOVE ' ', R8                    ; Print a space
                        RSUB IO$PUTCHAR, 1
                        RBRA _IO$DUMP_MEMORY_LOOP, 1    ; Continue the print loop
_IO$DUMP_MEMORY_EXIT    RSUB IO$PUT_CRLF, 1             ; Print a last CR/LF pair
                        MOVE R1, R8                     ; Restore R8,
                        DECRB                           ; switch back to the correct register page
			            RET
;
;***************************************************************************************
;* IO$GET_W_HEX reads four hex nibbles from stdin and returns the corresponding
;* value in R8
;*
;* Illegal characters (not 1-9A-F or a-f) will generate a bell signal. The only
;* exception to this behaviour is the character 'x' which will erase any input
;* up to this point. This has the positive effect that a hexadecimal value can
;* be entered as 0x.... or just as ....
;***************************************************************************************
;
IO$GET_W_HEX        INCRB                                   ; Get a new register page
_IO$GET_W_HEX_REDO  XOR     R0, R0                          ; Clear R0
                    MOVE    4, R1                           ; We need four characters
                    MOVE    IO$HEX_NIBBLES, R9              ; Pointer to list of valid chars
_IO$GET_W_HEX_INPUT RSUB    IO$GETCHAR, 1                   ; Read a character into R8
                    RSUB    CHR$TO_UPPER, 1                 ; Convert to upper case
                    CMP     'X', R8                         ; Was it an 'X'?
                    RBRA    _IO$GET_W_HEX_REDO, Z           ; Yes - redo from start :-)
                    RSUB    STR$STRCHR, 1                   ; Is it a valid character?
                    MOVE    R10, R10                        ; Result equal zero?
                    RBRA    _IO$GET_W_HEX_VALID, !Z         ; No
                    MOVE    CHR$BELL, R8                    ; Yes - generate a beep :-)
                    RSUB    IO$PUTCHAR, 1
                    RBRA    _IO$GET_W_HEX_INPUT, 1          ; Retry
_IO$GET_W_HEX_VALID RSUB    IO$PUTCHAR, 1                   ; Echo character
                    SUB     IO$HEX_NIBBLES, R10             ; Get number of character
                    SHL     4, R0
                    ADD     R10, R0
                    SUB     0x0001, R1
                    RBRA    _IO$GET_W_HEX_INPUT, !Z         ; Read next character
                    MOVE    R0, R8
                    DECRB                                   ; Restore previous register page
                    RET
;
;***************************************************************************************
;* IO$PUT_W_HEX prints a machine word in hexadecimal notation. 
;*
;* R8: Contains the machine word to be printed in hex notation.
;*
;* The contents of R8 are being preserved during the run of this function.
;***************************************************************************************
;
IO$PUT_W_HEX    INCRB                   ; Get a new register page
                MOVE 0x0004, R0         ; Save constant for nibble shifting
                MOVE R0, R4             ; Set loop counter to four
                MOVE R8, R5             ; Copy contents of R8 for later restore
                MOVE IO$HEX_NIBBLES, R1 ; Create a pointer to the list of nibbles
                                        ; Push four ASCII characters to the stack
_IO$PWH_SCAN    MOVE R1, R2             ; and create a scratch copy of this pointer
                MOVE R8, R3             ; Create a local copy of the machine word
                AND 0x000f, R3          ; Only the four LSBs are of interest
                ADD R3, R2              ; Adjust pointer to the desired nibble
                MOVE @R2, @--SP         ; and save the ASCII character to the stack
                SHR 4, R8               ; Shift R8 four places right
                SUB 0x0001, R4          ; Decrement loop counter
                RBRA _IO$PWH_SCAN, !Z   ; and continue with the next nibble
                                        ; Now read these characters back and print them
                MOVE R0, R4             ; Initialize loop counter
_IO$PWH_PRINT   MOVE @SP++, R8          ; Fetch a character from the stack
                RSUB IO$PUTCHAR, 1      ; and print it
                SUB 0x0001, R4          ; Decrement loop counter
                RBRA _IO$PWH_PRINT, !Z  ; and continue with the next character
                                        ; That is all...
                MOVE R5, R8             ; Restore contents of R8
                DECRB                   ; Restore correct register page
		        RET
;
;***************************************************************************************
;* IO$GETCHAR reads a character either from the first UART in the system or from an
;* attached USB keyboard. This depends on the setting of bit 0 of the switch register.
;* If SW[0] == 0, then the character is read from the UART, otherwise it is read from
;* the keyboard data register.
;*
;* R8 will contain the character read in its lower eight bits.
;***************************************************************************************
;
IO$GETCHAR          INCRB
                    MOVE    IO$SWITCH_REG, R0
_IO$GETCHAR_ENTRY   MOVE    @R0, R1                 ; Read the switch register
                    AND     0x0001, R1              ; Lowest bit set?
                    RBRA    _IO$GETCHAR_UART, Z     ; No, read from UART
                    RSUB    KBD$GETCHAR, 1          ; Yes, read from USB-keyboard
                    MOVE    IO$KBD_STATE, R3        ; Preserve modifier keys 
                    MOVE    @R3, R2                  
                    RBRA    _IO$GETCHAR_SPECIAL, 1  ; One char successfully read
_IO$GETCHAR_UART    RSUB    UART$GETCHAR, 1         ; Read from UART
                    MOVE    0, R2                   ; Make sure: no USB phantom modifiers
_IO$GETCHAR_SPECIAL CMP     KBD$CTRL_E, R8          ; CTRL-E?
                    RBRA    QMON$WARMSTART, Z       ; Return to monitor immediately!
                    CMP     KBD$CTRL_F, R8          ; CTRL-F?
                    RBRA    _IO$GETCHAR_SU1, Z      ; Yes: scroll up 1 line
                    CMP     KBD$CUR_DOWN, R8        ; No: Cursor Down key?
                    RBRA    _IO$GETCHAR_NO_FCD, !Z  ; No
_IO$GETCHAR_SU1     MOVE    1, R8                   ; VGA$SCROLL_UP_1 in manual mode
                    RSUB    VGA$SCROLL_UP_1, 1      ; Perform scroll up
                    RBRA    _IO$GETCHAR_ENTRY, 1    ; Wait for next character
_IO$GETCHAR_NO_FCD  CMP     KBD$CTRL_B, R8          ; CTRL-B?
                    RBRA    _IO$GETCHAR_SD1, Z      ; Yes: scroll down 1 line
                    CMP     KBD$CUR_UP, R8          ; No: Cursor Up key?
                    RBRA    _IO$GETCHAR_NO_BCU, !Z  ; No                    
_IO$GETCHAR_SD1     RSUB    VGA$SCROLL_DOWN_1, 1    ; Perform scroll down
                    RBRA    _IO$GETCHAR_ENTRY, 1    ; Wait for next character
_IO$GETCHAR_NO_BCU  AND     KBD$CTRL, R2            ; CTRL pressed?
                    RBRA    _IO$GETCHAR_NO_CTRL, Z  ; No
                    CMP     KBD$PG_DOWN, R8         ; Yes: CTRL+Page Down?
                    RBRA    _IO$GETCHAR_NO_CPGD, !Z ; No
                    MOVE    10, R8                  ; Yes: scroll up 10 lines
                    RSUB    VGA$SCROLL_UP,1
                    RBRA    _IO$GETCHAR_ENTRY, 1    ; Wait for next character
_IO$GETCHAR_NO_CPGD CMP     KBD$PG_UP, R8           ; CTRL+Page Up?
                    RBRA    _IO$GETCHAR_NO_CTRL, !Z ; No
                    MOVE    10, R8                  ; Yes: scroll down 10 lines
                    RSUB    VGA$SCROLL_DOWN, 1
                    RBRA    _IO$GETCHAR_ENTRY, 1    ; Wait for next character
_IO$GETCHAR_NO_CTRL CMP     KBD$PG_DOWN, R8         ; Page Down?
                    RBRA    _IO$GETCHAR_NO_PGD, !Z  ; No
                    MOVE    40, R8                  ; Yes: scroll up one screen
                    RSUB    VGA$SCROLL_UP, 1
                    RBRA    _IO$GETCHAR_ENTRY, 1    ; Wait for next character
_IO$GETCHAR_NO_PGD  CMP     KBD$PG_UP, R8           ; Page Up?
                    RBRA    _IO$GETCHAR_NO_PGU, !Z  ; No
                    MOVE    40, R8                  ; Yes: scroll down one screen
                    RSUB    VGA$SCROLL_DOWN, 1              
                    RBRA    _IO$GETCHAR_ENTRY, 1    ; Wait for next character
_IO$GETCHAR_NO_PGU  NOP                    
_IO$GETCHAR_FIN     DECRB
                    RET
;
;***************************************************************************************
;* IO$GETS reads a CR/LF terminated string from the serial line
;*
;* R8 has to point to a preallocated memory area to store the input line
;***************************************************************************************
;
IO$GETS         INCRB                  ; Get a new register page
                MOVE R8, R0            ; Save parameters
                MOVE R8, R1
_IO$GETS_LOOP   RSUB IO$GETCHAR, 1     ; Get a single character from the serial line
                MOVE R8, @R0++         ; Store it into the buffer area
                RSUB IO$PUTCHAR, 1     ; Echo the character
                SUB 0x000A, R8         ; Was it a LF character?
                RBRA _IO$GETS_LOOP, !Z ; No -> continue reading characters
                MOVE 0x000D, @R0++     ; Extend the string with a CR and
                MOVE 0x0000, @R0       ; terminate it with a null word
                MOVE R1, R8            ; Restore R8 which will now point to the string
                DECRB                  ; Restore the register page
		        RET
;
;***************************************************************************************
;* IO$PUTS prints a null terminated string.
;*
;* R8: Pointer to the string to be printed. Of each word only the lower eight bits
;*     will be printed. The terminating word has to be zero.
;*
;* The contents of R8 are being preserved during the run of this function.
;***************************************************************************************
;
IO$PUTS         INCRB                   ; Get a new register page
                MOVE R8, R1             ; Save contents of R8
                MOVE R8, R0             ; Local copy of the string pointer
_IO$PUTS_LOOP   MOVE @R0++, R8          ; Get a character from the string
                AND 0x00FF, R8          ; Only the lower eight bits are relevant
                RBRA _IO$PUTS_END, Z    ; Return when the string end has been reached
                RSUB IO$PUTCHAR, 1      ; Print this character
                RBRA _IO$PUTS_LOOP, 1   ; Continue with the next character
_IO$PUTS_END    MOVE R1, R8             ; Restore contents of R8
                DECRB                   ; Restore correct register page
        		RET
;
;***************************************************************************************
;* IO$PUT_CRLF prints actually a LF/CR (the reason for this is that curses on the
;*             MAC, where the emulation currently runs, has problems with CR/LF, but
;*             not with LF/CR)
;***************************************************************************************
;
IO$PUT_CRLF     INCRB                   ; Get a new register page
                MOVE R8, R0             ; Save contents of R8
                MOVE 0x0A, R8
                RSUB IO$PUTCHAR, 1
                MOVE 0x0D, R8
                RSUB IO$PUTCHAR, 1
                MOVE R0, R8             ; Restore contents of R8
                DECRB                   ; Return to previous register page
	        	RET
;
;***************************************************************************************
;* IO$PUTCHAR prints a single character.
;*
;* R8: Contains the character to be printed
;
;* The contents of R8 are being preserved during the run of this function.
;***************************************************************************************
;
IO$PUTCHAR          INCRB
                    MOVE    R8, R2              ; Avoid printing a zero character in...
                    AND     KBD$SPECIAL, R2     ; ...case somebody directly syscalls...
                    RBRA    _IO$PUTCHAR_END, !Z ; ...here with a special key in R8
                    MOVE    IO$SWITCH_REG, R0
                    MOVE    @R0, R1             ; Read the switch register
                    AND     0x0002, R1          ; Bit 1 set?
                    RBRA    _IO$PUTCHAR_UART, Z ; No, write to UART
                    RSUB    VGA$PUTCHAR, 1      ; Yes, write to VGA-controller
                    RBRA    _IO$PUTCHAR_END, 1  ; Finish
_IO$PUTCHAR_UART    RSUB    UART$PUTCHAR, 1
_IO$PUTCHAR_END     DECRB
                    RET
;
;***************************************************************************************
;* IO$TIL
;*
;* Show a four nibble hex value on the TIL-display
;*
;* R8: Contains the value to be displayed
;***************************************************************************************
;
IO$TIL          INCRB
                MOVE    IO$TIL_DISPLAY, R0
                MOVE    R8, @R0
                DECRB
                RET
;
;***************************************************************************************
; Constants, etc.
;***************************************************************************************
;
IO$HEX_NIBBLES      .ASCII_W "0123456789ABCDEF"
IO$COLON_DELIMITER  .ASCII_W ": "
