; 8051 Keyboard Wedge, by Simon Hosie - 1997,1998,2000
;
;	Inserts scancodes into the datastream between a keyboard and PC
;	representing the actions on joysticks.
;
;	Source code is meant to be viewed on a 132 column screen.

$NOLIST
$INCLUDE (keywedge.inc)
$LIST

; ----------------------------------------------------------------------------------------------

; Place the scancode queue after the first bank of registers.  There are 24
; bytes of RAM before bit memory that don't have a better use.

			DSEG	at 08h
QueueBase:		DS	QueueLength	; scancode queue

; ----------------------------------------------------------------------------------------------

			BSEG	at 0	; Data area containing single bit R/W registers

PC_TransError:		DBIT	1	; current transmission has gone awry
Kb_TransError:		DBIT	1

Kb_ToRespondNow:	DBIT	1	; next byte from keyboard should shortcut queue
PC_ByteFromQueue:	DBIT	1	; unqueue this byte when sent OK

QueueFull:		DBIT	1	; queue can't take any more data
Kb_Blocking:		DBIT	1	; we're holding the keyboard clock line low, not it
PC_SoftBlock:		DBIT	1	; PC has disabled scanning for some reason
Kb_DeferTimeout:	DBIT	1	; don't set usual timeout period

PowerupTimeout:		DBIT	1	; interrupt ocurred for powerup delay

EndOfBSEG:		DBIT	0	; label to find start of available byte space

; ----------------------------------------------------------------------------------------------

; Data that requires both bit and byte addressability.

			DSEG	at (EndOfBSEG + 7 + 256) / 8

LEDStateA:		DS	1	; generic indicators
;PC_TXIndicator		BIT	LEDStateA.0
;PC_RXIndicator		BIT	LEDStateA.1
;PC_BlockingIndicator	BIT	LEDStateA.2
;PC_ErrorIndicator	BIT	LEDStateA.3
;Kb_TXIndicator		BIT	LEDStateA.4
;Kb_RXIndicator		BIT	LEDStateA.5
;Kb_BlockingIndicator	BIT	LEDStateA.6
;Kb_ErrorIndicator	BIT	LEDStateA.7

LEDStateB:		DS	1	; more generic indicators
;MetaPrefixIndicator	BIT	LEDStateB.0
;Meta2PrefixIndicator	BIT	LEDStateB.1
;ReleasePrefixIndicator	BIT	LEDStateB.2
;RespondNowIndicator	BIT	LEDStateB.3
;QueueOverrunIndicator	BIT	LEDStateB.6
;QueueFullIndicator	BIT	LEDStateB.7

DIPSwitchState:		DS	1	; generic switches
TransparentSwitch	BIT	DIPSwitchState.0
DvorakSwitch		BIT	DIPSwitchState.1
DropWinkeySwitch	BIT	DIPSwitchState.2
IndicatorBankSwitch	BIT	DIPSwitchState.7

Kb_RcvCodes:		DS	1	; Bitfield to define complete keystroke
Kb_Meta2Prefixed	BIT	Kb_RcvCodes.0	; Prefix E1 to the whole thing
Kb_DoubleCode		BIT	Kb_RcvCodes.1	; Double-code keystroke
Kb_MetaPre2fixed	BIT	Kb_RcvCodes.2	; Prefix E0 to prefixed code
Kb_ReleasePre2fixed	BIT	Kb_RcvCodes.3	; Prefix F0 to prefixed code
Kb_MetaPrefixed		BIT	Kb_RcvCodes.4	; Prefix E0 to primary code
Kb_ReleasePrefixed	BIT	Kb_RcvCodes.5	; Prefix F0 to primary code
Kb_GotCode		BIT	Kb_RcvCodes.6	; got the code itself (unused)

PC_SndCodes:		DS	1
PC_Meta2Prefixed	BIT	PC_SndCodes.0	; Prefix E1 to the whole thing
PC_DoubleCode		BIT	PC_SndCodes.1	; Double-code keystroke
PC_MetaPre2fixed	BIT	PC_SndCodes.2	; Prefix E0 to prefixed code
PC_ReleasePre2fixed	BIT	PC_SndCodes.3	; Prefix F0 to prefixed code
PC_MetaPrefixed		BIT	PC_SndCodes.4	; Prefix E0 to primary code
PC_ReleasePrefixed	BIT	PC_SndCodes.5	; Prefix F0 to primary code
PC_SendMainCode		BIT	PC_SndCodes.6	; send the code itself

; ----------------------------------------------------------------------------------------------

; Normal byte data

Kb_ExtraCode:		DS	1	; first code of double-code keystroke
PC_ExtraCode:		DS	1
PC_MainCode:		DS	1	; have to hold the main code somewhere when sending

Kb_ShiftBuffer:		DS	1	; workspace for transfer
PC_ShiftBuffer:		DS	1

PC_LastByteSent:	DS	1	; for resend requests
Kb_LastByteSent:	DS	1

PowerupCountdown:	DS	1	; extension on timer 1 for powerup delay
PollCountdown:		DS	1	; countdown to joystick poll

KeyboardState:		DS	NumJoysticks	; state of joystick buttons
JoystickState:		DS	NumJoysticks	; state of keys that map to joystick buttons

StackBase:		DS	20h	; put the stack here

; ##############################################################################################

			CSEG	at RESET
ResetPt:		ajmp	Main				; <- Click here to begin

			CSEG	at EXTI0
			clr	PC_IntEnable			; goes low when PC blocks
			clr	PC_TimerRun			; (level triggered)
			setb	PC_Data
			ajmp	PC_LowInt

			CSEG	at TIMER0
			clr	PC_TimerRun			; time to change PC clock state
			push	PSW
			push	ACC
			ajmp	PC_TimerInt

			CSEG	at EXTI1
			clr	Kb_TimerRun			; keyboard clock dropped
			push	PSW
			push	ACC
			ajmp	Kb_EdgeInt

			CSEG	at TIMER1
			ajmp	Kb_TimerInt			; keyboard timed out or
								; miscellaneous event

; ##############################################################################################

; Notice indicating who done it.

			DB	'Joystick KeyWedge, Simon Hosie 2000'

; ##############################################################################################
; ##############################################################################################

; 'Super Hoopy Data Throughpy' transparency mode.
;	State machine to minimise response times to changes in lines, useful
;	for situations that can't be resolved by general simulation such as
;	unexpected protocol extensions or strange powerup conditions.

;	Each state begins by setting outputs to match inputs, then waiting
;	for an input to change and branching to the new state which will in
;	turn reconfigure outputs to fit and wait for the next change. 
;	Extremely inefficient in terms of ROM usage, but reliable.

TransparentMode:	clr	A
State00:		mov	P3, #P3_DefaultState - (0)	; set new output state
;			mov	P1, #P3_DefaultState - (0)	; shadow for protocol snooping
			mov	TH1, A				; defer timeout due to activity
State00L:		jnb	Kb_Clock, State20
			jnb	PC_Clock, State10
			jnb	Kb_Data, State02
			jb	PC_Data, State00L

State01:		mov	P3, #P3_DefaultState - (Kb_DataMask)
;			mov	P1, #P3_DefaultState - (Kb_DataMask)
			mov	TH1, A
State01L:		jnb	Kb_Clock, State21
			jnb	PC_Clock, State11
			jb	PC_Data, State00
			sjmp	State01L

State02:		mov	P3, #P3_DefaultState - (PC_DataMask)
;			mov	P1, #P3_DefaultState - (PC_DataMask)
			mov	TH1, A
State02L:		jnb	Kb_Clock, State22
			jnb	PC_Clock, State12
			jb	Kb_Data, State00
			sjmp	State02L

State10:		mov	P3, #P3_DefaultState - (Kb_ClockMask)
;			mov	P1, #P3_DefaultState - (Kb_ClockMask)
			mov	TH1, A
State10L:		jb	PC_Clock, State00
			jnb	Kb_Data, State12
			jb	PC_Data, State10L

State11:		mov	P3, #P3_DefaultState - (Kb_ClockMask+Kb_DataMask)
;			mov	P1, #P3_DefaultState - (Kb_ClockMask+Kb_DataMask)
			mov	TH1, A
State11L:		jb	PC_Clock, State01
			jb	PC_Data, State10
			sjmp	State11L

State12:		mov	P3, #P3_DefaultState - (Kb_ClockMask+PC_DataMask)
;			mov	P1, #P3_DefaultState - (Kb_ClockMask+PC_DataMask)
			mov	TH1, A
State12L:		jb	PC_Clock, State02
			jb	Kb_Data, State10
			sjmp	State12L

State20:		mov	P3, #P3_DefaultState - (PC_ClockMask)
;			mov	P1, #P3_DefaultState - (PC_ClockMask)
			mov	TH1, A
State20L:		jb	Kb_Clock, State00
			jnb	Kb_Data, State22
			jb	PC_Data, State20L

State21:		mov	P3, #P3_DefaultState - (PC_ClockMask+Kb_DataMask)
;			mov	P1, #P3_DefaultState - (PC_ClockMask+Kb_DataMask)
			mov	TH1, A
State21L:		jb	Kb_Clock, State01
			jb	PC_Data, State20
			sjmp	State21L

State22:		mov	P3, #P3_DefaultState - (PC_ClockMask+PC_DataMask)
;			mov	P1, #P3_DefaultState - (PC_ClockMask+PC_DataMask)
			mov	TH1, A
State22L:		jb	Kb_Clock, State02
			jb	Kb_Data, State20
			sjmp	State22L

; ##############################################################################################
; ##############################################################################################

JmpAPlusDPtr:		jmp	@A+DPTR				; used in lieu of a relative call

PC_TimerTable:		ajmp	PC_TimerTable
  PC_SendStatePtr:	ajmp	PC_RaiseClock
			ajmp	PC_SendDataBit
			ajmp	PC_RaiseClock
			ajmp	PC_SendDataBit
			ajmp	PC_RaiseClock
			ajmp	PC_SendDataBit
			ajmp	PC_RaiseClock
			ajmp	PC_SendDataBit
			ajmp	PC_RaiseClock
			ajmp	PC_SendDataBit
			ajmp	PC_RaiseClock
			ajmp	PC_SendDataBit
			ajmp	PC_RaiseClock
			ajmp	PC_SendDataBit
			ajmp	PC_RaiseClock
			ajmp	PC_SendDataBit
			ajmp	PC_RaiseClock
			ajmp	PC_SendParityBit
			ajmp	PC_RaiseClock
			ajmp	PC_SendStopBit
			ajmp	PC_FinishSend
  PC_NextByteStatePtr:	ajmp	PC_SendNextOrIdle
  			ajmp	ResetPt

  PC_RecvStatePtr:	ajmp	PC_DropClock
			ajmp	PC_RecvDataBit
			ajmp	PC_DropClock
			ajmp	PC_RecvDataBit
			ajmp	PC_DropClock
			ajmp	PC_RecvDataBit
			ajmp	PC_DropClock
			ajmp	PC_RecvDataBit
			ajmp	PC_DropClock
			ajmp	PC_RecvDataBit
			ajmp	PC_DropClock
			ajmp	PC_RecvDataBit
			ajmp	PC_DropClock
			ajmp	PC_RecvDataBit
			ajmp	PC_DropClock
			ajmp	PC_RecvDataBit
			ajmp	PC_DropClock
			ajmp	PC_RecvParityBit
			ajmp	PC_DropClock
			ajmp	PC_RecvStopBit
			ajmp	PC_DropClock
			ajmp	PC_EndAcknowledge
			ajmp	ResetPt

  PC_LowClockStatePtr:	ajmp	PC_CheckLowClock
  			ajmp	ResetPt

Kb_EdgeTable:
  Kb_WaitingStatePtr:	ajmp	Kb_RecvStartBit
			ajmp	Kb_RecvDataBit
			ajmp	Kb_RecvDataBit
			ajmp	Kb_RecvDataBit
			ajmp	Kb_RecvDataBit
			ajmp	Kb_RecvDataBit
			ajmp	Kb_RecvDataBit
			ajmp	Kb_RecvDataBit
			ajmp	Kb_RecvDataBit
			ajmp	Kb_RecvParityBit
			ajmp	Kb_RecvStopBit
			ajmp	ResetPt

  Kb_SendStatePtr:	ajmp	Kb_SendDataBit
			ajmp	Kb_SendDataBit
			ajmp	Kb_SendDataBit
			ajmp	Kb_SendDataBit
			ajmp	Kb_SendDataBit
			ajmp	Kb_SendDataBit
			ajmp	Kb_SendDataBit
			ajmp	Kb_SendDataBit
			ajmp	Kb_SendParityBit
			ajmp	Kb_SendStopBit
			ajmp	Kb_SeeAcknowledge
			ajmp	ResetPt

; ##############################################################################################
; ##############################################################################################

; If the PC clock line is driven low while this IRQ is enabled then we
; didn't expect it.  Abandon any data transfer and start polling the line at
; a moderate rate.  Thus far there is no reason to abort any communications
; with the keyboard or stop polling joysticks.

PC_LowInt:		mov	PC_StateIndex, #PC_LowClockStatePtr - PC_TimerTable
			PC_SetupTimer BlockPollTime
			reti

; ----------------------------------------------------------------------------------------------

PC_TimerInt:		push	DPL
			push	DPH
			mov	DPTR, #PC_TimerTable
			mov	A, PC_StateIndex
			inc	PC_StateIndex
			inc	PC_StateIndex
			acall	JmpAPlusDPtr
			pop	DPH
			pop	DPL
			pop	ACC
			pop	PSW
			reti

; ----------------------------------------------------------------------------------------------

Kb_EdgeInt:		push	DPL
			push	DPH
			mov	DPTR, #Kb_EdgeTable
			mov	A, Kb_StateIndex
			inc	Kb_StateIndex
			inc	Kb_StateIndex
			acall	JmpAPlusDPtr
			jbc	Kb_DeferTimeout, Kb_WithoutTimeout
			Kb_SetupTimer ClockPeriodTimeout
Kb_WithoutTimeout:	pop	DPH
			pop	DPL
			pop	ACC
			pop	PSW
			reti

; ----------------------------------------------------------------------------------------------

; Check all sorts of miscellaneous conditions here.  The keyboard timeout is
; the least timing critical and so it's multiplexed with other non-critical
; timers.
;
; If the PowerupTimeout bit is set then we're currently pretending to be
; transparent for fear of striking trouble with the power up sequence. 
; Count that down and at timeout break out of the currently running
; function.
;
; If we're in 'SendState' then we've been holding the clock and data lines
; low to indicate to the keyboard that we want to send data.  That time is
; up, so begin the transfer.
;
; Otherwise something has gone wrong.  Flag the transfer as bad.

Kb_TimerInt:		jnb	PowerupTimeout, Kb_NotPowerupInt
			djnz    PowerupCountdown, PowerupDontFinish
			clr	PowerupTimeout
			clr	Kb_TimerRun
			dec	SP				; break out of current function
			dec	SP				; (known to be TransparentMode)
PowerupDontFinish:	reti

Kb_NotPowerupInt:	clr	Kb_TimerRun
			cjne	Kb_StateIndex, #Kb_SendStatePtr - Kb_EdgeTable, Kb_NotSendSetup
			clr	Kb_IntFlag
			setb	Kb_Clock
			setb	Kb_IntEnable
			Kb_SetupTimer ClockPeriodTimeout
			reti

Kb_NotSendSetup:	clr	Kb_ToRespondNow
			push	PSW
			cjne	Kb_StateIndex, #0, Kb_TransTimeout
			pop	PSW
			reti
Kb_TransTimeout:	setb	Kb_TransError
			mov	Kb_StateIndex, #0
Kb_NoTransTimeout:	pop	PSW
			reti

; ##############################################################################################

; A bunch of small modules that are executed as dictated by the jump tables. 
; Each module does little or no more than what its label indicates.

PC_RaiseClock:		setb	PC_Clock
			setb	PC_IntEnable
			PC_SetupTimer ClockPhase
			ret

PC_DropClock:		clr	PC_IntEnable
			clr	PC_Clock
PC_SetupNextPhase:	PC_SetupTimer ClockPhase
			ret

; ----------------------------------------------------------------------------------------------

PC_SendDataBit:		mov	A, PC_ShiftBuffer
			mov	C, ACC.0
			mov	PC_Data, C
			rr	A
			mov	PC_ShiftBuffer, A
			ajmp	PC_DropClock

PC_SendParityBit:	mov	A, PC_ShiftBuffer
			mov	C, P
			cpl	C
			mov	PC_Data, C
			cje	A, #ResendCode, PC_DropClock
			mov	PC_LastByteSent, A
			ajmp	PC_DropClock

PC_SendStopBit:		setb	PC_Data
			ajmp	PC_DropClock

PC_FinishSend:		setb	PC_Clock
			setb	PC_IntEnable
			PC_SetupTimer PostByteDelay		; for badly written software
			ret

PC_SendNextOrIdle:	mov	PC_StateIndex, #0
			ajmp	PC_SentByte

; ----------------------------------------------------------------------------------------------

PC_RecvDataBit:		setb	PC_Clock
			setb	PC_IntEnable
			mov	C, PC_Data
			mov	A, PC_ShiftBuffer
			rrc	A
			mov	PC_ShiftBuffer, A
			ajmp	PC_SetupNextPhase

PC_RecvParityBit:	setb	PC_Clock
			setb	PC_IntEnable
			mov	C, PC_Data
			mov	A, PC_ShiftBuffer
			jb	P, PC_WantParity0
			cpl	C
PC_WantParity0:		orl	C, PC_TransError
			mov	PC_TransError, C
			ajmp	PC_SetupNextPhase

PC_RecvStopBit:		setb	PC_Clock
			setb	PC_IntEnable
			jb	PC_Data, PC_Acknowledge
			setb	PC_TransError
			dec	PC_StateIndex			; try to clock in a stop bit
			dec	PC_StateIndex			; before continuing
			dec	PC_StateIndex
			dec	PC_StateIndex
			ajmp	PC_SetupNextPhase

PC_Acknowledge:		clr	PC_Data
			ajmp	PC_SetupNextPhase

PC_EndAcknowledge:	setb	PC_Clock
			setb	PC_IntEnable
			setb	PC_Data
			mov	PC_StateIndex, #0
			mov	A, PC_ShiftBuffer
			cjne	A, #ResendCode, PC_NotResendReq
			mov	A, PC_LastByteSent
			ajmp	PC_StartSend
PC_NotResendReq:	ajmp	PC_GotByte

; ----------------------------------------------------------------------------------------------

PC_CheckLowClock:	jb	PC_Clock, PC_ClockRaised
			mov	PC_StateIndex, #PC_LowClockStatePtr - PC_TimerTable
			PC_SetupTimer BlockPollTime
			ret

PC_ClockRaised:		setb	PC_IntEnable
			jb	PC_Data, PC_JustBlocking
			clr	PC_TransError
			mov	PC_StateIndex, #PC_RecvStatePtr - PC_TimerTable
			PC_SetupTimer ClockPhase
			ret

PC_JustBlocking:	mov	PC_StateIndex, #PC_NextByteStatePtr - PC_TimerTable
			PC_SetupTimer PostByteDelay
			ret

; ----------------------------------------------------------------------------------------------

Kb_RecvStartBit:	mov	C, Kb_Data
			mov	Kb_TransError, C
			ret

Kb_RecvDataBit:		mov	C, Kb_Data
			mov	A, Kb_ShiftBuffer
			rrc	A
			mov	Kb_ShiftBuffer, A
			ret

Kb_RecvParityBit:	mov	C, Kb_Data
			mov	A, Kb_ShiftBuffer
			jb	P, Kb_WantParity0
			cpl	C
Kb_WantParity0:		orl	C, Kb_TransError
			mov	Kb_TransError, C
			ret

Kb_RecvStopBit:		mov	C, Kb_Data
			cpl	C
			orl	C, Kb_TransError
			mov	Kb_TransError, C
			mov	Kb_StateIndex, #0
			setb	Kb_DeferTimeout
			jnc	Kb_RecvOK
			mov	A, Kb_LastByteSent
			jb	Kb_ToRespondNow, Kb_ResendCommand
			mov	A, #ResendCode
Kb_ResendCommand:	ajmp	Kb_StartSend
Kb_RecvOK:		mov	A, Kb_ShiftBuffer
			cjne	A, #ResendCode, Kb_NotResendReq
			mov	A, Kb_LastByteSent
			ajmp	Kb_StartSend
Kb_NotResendReq:	clr     Kb_Clock
			acall	Kb_GotByte
			jb	Kb_Blocking, Kb_DontRaiseClock
			clr	Kb_IntFlag
			setb	Kb_Clock
Kb_DontRaiseClock:	ret

; ----------------------------------------------------------------------------------------------

Kb_SendDataBit:		mov	A, Kb_ShiftBuffer
			mov	C, ACC.0
			mov	Kb_Data, C
			rr	A
			mov	Kb_ShiftBuffer, A
			ret

Kb_SendParityBit:	mov	A, Kb_ShiftBuffer
			mov	C, P
			cpl	C
			mov	Kb_Data, C
			cjne	A, #ResendCode, Kb_NotResendCode
			ret
Kb_NotResendCode:	mov	Kb_LastByteSent, A
			ret

Kb_SendStopBit:		setb	Kb_Data
			ret

Kb_SeeAcknowledge:	mov	Kb_StateIndex, #0
			setb	Kb_DeferTimeout
			jb	Kb_Data, Kb_AckFailed
			ajmp	Kb_SentByte
Kb_AckFailed:		ret

; ##############################################################################################

; We got a byte from the PC.  All we know how to do is send it on to the
; keyboard and wait for its response.

PC_GotByte:		setb	Kb_ToRespondNow
			ajmp	Kb_StartSend

; ----------------------------------------------------------------------------------------------

; We got a byte from the keyboard.  If we were expecting a response to a
; command then check that it's valid and send it on if it is.  Otherwise
; analyse and/or queue it.

Kb_GotByte:		jnb	Kb_ToRespondNow, Kb_DontRespondNow
			cmp	A, #90h				; scancodes aren't responses
			jc	Kb_NotResponseCode
			cje	A, #MetaCode, Kb_NotResponseCode
			cje	A, #Meta2Code, Kb_NotResponseCode
			cje	A, #ReleaseCode, Kb_NotResponseCode
			clr	Kb_ToRespondNow			; we got something we can use as
			clr	PC_ByteFromQueue		; a response
			ajmp	PC_StartSend
Kb_NotResponseCode:	Kb_SetupTimer ResponseTimeout

Kb_DontRespondNow:	jnb	Kb_Meta2Prefixed, Kb_NotExtraCode
			jb	Kb_DoubleCode, Kb_NotExtraCode
			cjne	A, #MetaCode, Kb_NotPre2fixMeta
			setb	Kb_MetaPre2fixed
			ret
Kb_NotPre2fixMeta:	cjne	A, #ReleaseCode, Kb_NotPRe2fixRelease
			setb	Kb_ReleasePre2fixed
			ret
Kb_NotPre2fixRelease:	setb	Kb_DoubleCode
			mov	Kb_ExtraCode, A
			ret
Kb_NotExtraCode:	cjne	A, #Meta2Code, Kb_NotMeta2Code
			setb	Kb_Meta2Prefixed
			ret
Kb_NotMeta2Code:	cjne	A, #MetaCode, Kb_NotMetaCode
			setb	Kb_MetaPrefixed
			ret
Kb_NotMetaCode:		cjne	A, #ReleaseCode, Kb_NotReleaseCode
			setb	Kb_ReleasePrefixed
			ret
Kb_NotReleaseCode:	jnb	DvorakSwitch, Kb_DontTranslate
			jb	Kb_MetaPrefixed, Kb_DontTranslate
			jb	Kb_MetaPre2fixed, Kb_DontTranslate
			cmp	A, #15h				; perform Dvorak translation
			jc	Kb_DontTranslate
			cmp	A, #5ch
			jnc	Kb_DontTranslate
			mov	DPTR, #DvorakTransTable - 15h
			movc	A, @A+DPTR
Kb_DontTranslate:	jb      Kb_Meta2Prefixed, Kb_DontDiscard1
			jb      Kb_MetaPrefixed, Kb_DontDiscard1
;			acall   Kb_CheckCode			; Discard conflicting scancodes
;			jnc	Kb_DontDiscard1
;			mov	Kb_RcvCodes, #0
;			ret
Kb_DontDiscard1:	jnb	DropWinkeySwitch, Kb_DontDiscard2
			jnb	Kb_MetaPrefixed, Kb_DontDiscard2
			cjne	A, #WinMenuCode, Kb_DontDiscard2
			mov	Kb_RcvCodes, #0
			ret
Kb_DontDiscard2:	mov	R4, Kb_RcvCodes
			mov	R5, Kb_ExtraCode
			acall	QueueCode
			mov	Kb_RcvCodes, #0
			jnc	Kb_DontStartBlocking
			setb	Kb_Blocking
			clr	Kb_IntEnable
			clr	Kb_Clock
Kb_DontStartBlocking:	ret

; ==============================================================================================

; Begin sending to the PC.  This is a low priority job, if anything else is
; already going on then don't bother trying.

PC_StartSend:		clr	PC_IntEnable
			clr	PC_Data
			clr	PC_Clock
			mov	PC_ShiftBuffer, A
			mov	PC_StateIndex, #PC_SendStatePtr - PC_TimerTable
			PC_SetupTimer ClockPhase
			ret

; ----------------------------------------------------------------------------------------------

; We sent a byte to the PC successfully.  If it came from the queue then get
; rid of it.

PC_SentByte:		jnb	PC_ByteFromQueue, PC_ProcessQueue ; reset queued code if interrupted
			clr	A
			cjne	A, PC_SndCodes, PCSB_DoMore
;			acall	UnqueueCode
			mov	QueueEndPtr, #QueueBase

PC_ProcessQueue:	acall	PeekQueue
			jnc	PC_SendCode
			clr	PC_ByteFromQueue
			ret

PC_SendCode:		setb	PC_ByteFromQueue
			mov	PC_SndCodes, R4
			mov	PC_ExtraCode, R5
			mov	PC_MainCode, A
			setb	PC_SendMainCode
PCSB_DoMore:		mov	A, #Meta2Code
			jbc	PC_Meta2Prefixed, PC_StartSend
			jnb	PC_DoubleCode, PCSC_NotDoubleCode
			mov	A, #MetaCode
			jbc	PC_MetaPre2fixed, PC_StartSend
			mov	A, #ReleaseCode
			jbc	PC_ReleasePre2fixed, PC_StartSend
			clr	PC_DoubleCode
			mov	A, PC_ExtraCode
			ajmp	PC_StartSend
PCSC_NotDoubleCode:	mov	A, #MetaCode
			jbc	PC_MetaPrefixed, PC_StartSend
			mov	A, #ReleaseCode
			jbc	PC_ReleasePrefixed, PC_StartSend
			mov	PC_SndCodes, #0
			mov	A, PC_MainCode
			ajmp	PC_StartSend

; ==============================================================================================

Kb_StartSend:		clr	Kb_IntEnable
			clr	Kb_Clock
			clr	Kb_Data
			mov	Kb_ShiftBuffer, A
			mov	Kb_StateIndex, #Kb_SendStatePtr - Kb_EdgeTable
			Kb_SetupTimer BlockHoldTime
			ret

; ----------------------------------------------------------------------------------------------

; We send a byte to the keyboard successfully.  Expect a reply.

Kb_SentByte:		Kb_SetupTimer ResponseTimeout
			ret

; ##############################################################################################

; Push data into the queue.  A is the scancode, R4 is the code map, and R5
; is the extra code (if any).  Once data is queued, check to see if anything
; can be sent out.  Carry set on return indicates the queue is full.

QueueCode:		mov	C, EA
			clr	EA
			QuickQueue AR4
			QuickQueue AR5
			QuickQueue A
			mov	EA, C

			cjne	PC_StateIndex, #0, QC_JustQueueIt
			jb	Kb_ToRespondNow, QC_JustQueueIt
			push	ACC
			acall	PC_ProcessQueue
			pop	ACC
QC_JustQueueIt:		cmp	QueueEndPtr, #QueueBase + QueueThreshold
			cpl	C
			mov	QueueFull, C
			ret

; ----------------------------------------------------------------------------------------------

; Pull the bottom three bytes out of the stack.

UnqueueCode:		cmp	QueueEndPtr, #QueueBase + 3
			jc	UC_QueueEmpty
			push	AR1
			push	AR2
			mov	C, EA
			mov	F0, C
			clr	EA
			mov	R2, AQueueEndPtr
			mov	R0, #QueueBase
			mov	R1, #QueueBase + 3
			sjmp	UC_LoopEntry
UC_Loop:		mov	A, @R1
			mov	@R0, A
			inc	R0
			inc	R1
UC_LoopEntry:		mov	A, R1
			cjne	A, AR2, UC_Loop
			mov	C, F0
			mov	EA, C
			pop	AR2
			pop	AR1
UC_QueueEmpty:		cmp	QueueEndPtr, #QueueBase + QueueThreshold
			cpl	C
			mov	QueueFull, C
			jc	UC_DontUnblock
			jbc	Kb_Blocking, UC_UnqueueAndUnblock
UC_DontUnblock:		ret
UC_UnqueueAndUnblock:	clr	Kb_IntFlag
			setb	Kb_Clock
			setb	Kb_IntEnable
			ret

; ----------------------------------------------------------------------------------------------

; Fills Accumulator, R4 and R5, and clears carry to indicate a valid return
; (carry set means the queue is empty).

PeekQueue:		cmp	QueueEndPtr, #QueueBase + 3
			jc	PQ_Empty
			mov	R4, QueueBase
			mov	R5, QueueBase+1
			mov	A, QueueBase+2
			ret
PQ_Empty:		clr	A
			mov	R4, A
			mov	R5, A
			ret

; ##############################################################################################
IF 0
; See if this code is already marked as being down.

Kb_CheckCode:		push	ACC
			push	AR1
			acall	FindScanCode
			jc	KbCC_LookCloser
			pop	AR1
			pop	ACC
			ret
KbCC_LookCloser:	push	AR2
			mov	R2, AR1
			push	ACC
			add	A, #KeyboardState
			mov	R1, A
			mov	A, @R1
			push	AR1
			mov	R1, AR2
			mov	C, Kb_ReleasePrefixed
			cpl	C
			acall	CarryToBitN
			pop	AR1
			mov	@R1, A
			pop	ACC
			jb	Kb_ReleasePrefixed, KbCC_ConsiderBlocking
			pop	AR2
			pop	AR1
			pop	ACC
			clr	C
			ret
KbCC_ConsiderBlocking:	add	A, #JoystickState
			mov	R1, A
			mov	A, @R1
			mov	R1, AR2
			acall	BitNToCarry
			pop	AR2
			pop	AR1
			pop	ACC
			ret

; ----------------------------------------------------------------------------------------------

FindScanCode:		mov	DPTR, #JoystickCodes
			push	AR2
			mov	R2, A
			mov	R1, #NumJoysticks * 8
FSC_Loop:		clr     A
			movc	A, @A+DPTR
			xrl	A, R2
			jz	FSC_GotIt
			inc	DPTR
			djnz	R1, FSC_Loop
			clr	C
			pop	AR2
			ret
FSC_GotIt:		mov	A, #NumJoysticks * 8
			sub	A, R1
			mov	R1, A
			anl	A, #07h
			xch	A, R1
			rr	A
			rr	A
			rr	A
			anl	A, #1fh
			pop	AR2
			setb	C
			ret

; ----------------------------------------------------------------------------------------------

BitNToCarry:		cjne    R1, #0, BNC_ShiftLoop
			mov	C, ACC.0
			ret
BNC_ShiftLoop:		rr	A
			djnz	R1, BNC_ShiftLoop
			mov	C, ACC.0
			ret

; ----------------------------------------------------------------------------------------------

CarryToBitN:		push    PSW
			cjne	R1, #0, CBN_DoSomething
			pop     PSW
			mov	ACC.0, C
			ret
CBN_DoSomething:	pop     PSW
			push	AR1
CBN_ShiftLoop1:		rr	A
			djnz	R1, CBN_ShiftLoop1
			mov	ACC.0, C
			pop	AR1
CBN_ShiftLoop2:		rl	A
			djnz	R1, CBN_ShiftLoop2
			ret
ENDIF
; ##############################################################################################

PollAllJoysticks:	acall	ForceDIPSwitchUpdate
			mov	R1, #JoystickState
			mov	DPTR, #JoystickCodes
			mov	R2, #NumJoysticks
PAJ_Loop:		push	AR2
			acall	PollJoystick
			pop	AR2
			djnz	R2, PAJ_Loop
			ret

; ----------------------------------------------------------------------------------------------

PollJoystick:		acall	NextJoystick
			mov	A, JoystickPort

			mov	R4, #8
			mov	R2, A
			xrl	A, @R1
			mov	@R1, AR2
			push	ACC
			mov	A, R1
			add	A, #KeyboardState-JoystickState
			push	AR1
			mov	R1, A
			mov	AR3, @R1
			pop	AR1
			pop	ACC

PJ_Loop:		jnb	ACC.0, PJ_NotThisBit
			jb	QueueFull, PJ_NotThisBit
			push	ACC
			mov	A, R3
			jb	ACC.0, PJ_KeyAlreadyDown
			mov	A, R2
			mov	C, ACC.0
			clr	A
			movc	A, @A+DPTR
			mov	R4, #0
			jc	PJ_ReleaseCode
			mov	R4, #00100000b
PJ_ReleaseCode:		mov	R5, #0
			acall	QueueCode
PJ_KeyAlreadyDown:	pop	ACC
			clr	ACC.0
PJ_NotThisBit:		rr	A
			xch	A, R2
			rr	A
			xch	A, R2
			xch	A, R3
			rr	A
			xch	A, R3
			inc	DPTR
			djnz	R4, PJ_Loop
			xrl	A, @R1
			mov	@R1, A
			inc	R1
			ret

; ##############################################################################################

ForceLEDUpdate:		setb	Js_OutputDisable
			setb	Js_ResetStrobe
			clr	Js_ResetStrobe
			mov	A, LEDStateA
			jnb	IndicatorBankSwitch, FLU_BankAOK
			mov	A, LEDStateB
FLU_BankAOK:		mov	P1, A
			clr	Js_LEDLatchStrobe
			setb	Js_LEDLatchStrobe
			mov	P1, #0ffh
			ret

NextJoystick:		setb	Js_OutputDisable
			clr	Js_IncrementStrobe
			setb	Js_IncrementStrobe
			clr	Js_OutputDisable
			ret

ForceDIPSwitchUpdate:	acall	ForceLEDUpdate
			acall	NextJoystick
			mov	DIPSwitchState, P1
			ret

; ##############################################################################################

; Basically just show a whole lot of rubbish on the LEDs for debugging. 
; This is redundant once the code is deemed functional, but there's no good
; reason to remove it unless half the ROM goes missing or something like
; that.  If you don't need it then don't mount those components on the PCB. 
; Maybe someone will build an extension module to control disco lights based
; on keystrokes.

IF 0
UpdateIndicators:	cmp	PC_StateIndex, #PC_SendStatePtr-PC_TimerTable
			mov	F0, C
			cmp	PC_StateIndex, #PC_NextByteStatePtr-PC_TimerTable
			anl	C, /F0
			mov	PC_TXIndicator, C

			cmp	PC_StateIndex, #PC_RecvStatePtr-PC_TimerTable
			mov	F0, C
			cmp	PC_StateIndex, #PC_LowClockStatePtr-PC_TimerTable
			anl	C, /F0
			mov	PC_RXIndicator, C

			cmp	Kb_StateIndex, #Kb_SendStatePtr-Kb_EdgeTable
			cpl	C
			mov	Kb_TXIndicator, C

			cmp	Kb_StateIndex, #Kb_WaitingStatePtr+2-Kb_EdgeTable
			mov	F0, C
			cmp	Kb_StateIndex, #Kb_SendStatePtr-Kb_EdgeTable
			anl	C, /F0
			mov	Kb_RXIndicator, C

			cmp	PC_StateIndex, #PC_LowClockStatePtr-PC_TimerTable
			cpl	C
			mov	PC_BlockingIndicator, C

			mov	C, Kb_Blocking
			mov	Kb_BlockingIndicator, C

			mov	A, QueueEndPtr
			cmp	A, #QueueBase+QueueThreshold
			cpl	C
			mov	QueueFullIndicator, C

			cmp	A, #QueueBase+QueueLength
			cpl	C
			mov	QueueOverrunIndicator, C

			mov	C, PC_TransError
			mov	PC_ErrorIndicator, C
			mov	C, Kb_TransError
			mov	Kb_ErrorIndicator, C

			mov	C, Kb_MetaPrefixed
			mov	MetaPrefixIndicator, C
			mov	C, Kb_MetaPrefixed
			mov	Meta2PrefixIndicator, C
			mov	C, Kb_ReleasePrefixed
			mov	ReleasePrefixIndicator, C
			mov	C, Kb_ToRespondNow
			mov	RespondNowIndicator, C
ELSE
UpdateIndicators:	mov	LEDStateA, PC_MainCode
			mov	LEDStateB, PC_SndCodes
ENDIF
			ret

; ##############################################################################################

Main:			mov	IE, #0				; set up general operating
			mov	SP, #StackBase - 1		; parameters
			clr	A				; stack a return to reset
			push	ACC
			push	ACC
			mov	P1, #0ffh
			mov	P3, #P3_DefaultState
			mov	TCON, #04h
			mov	TMOD, #11h
			mov	IP, #06h

			mov	R0, #127			; wipe everything to make sure
			clr	A
ClearRAMLoop:		mov	@R0, A
			djnz	R0, ClearRAMLoop		; misses address 0, but R0 is
								; address zero, so it's OK.

			mov	QueueEndPtr, #QueueBase		; set up variables

			clr	Js_ResetStrobe			; reset address chip with two
			setb	Js_ResetStrobe			; _good_ edges (however the
			clr	Js_ResetStrobe			; lines were waggled before is
								; undefined)

			mov	IE, #08h			; prepare timer 1 only

			mov	LEDStateA, #033h		; show that we're in
			mov	LEDStateB, #055h		; show that we're in
			acall	ForceDIPSwitchUpdate		; transparent mode
			acall	ForceLEDUpdate

			mov	PowerupCountdown, #4ch		; about 2.5 seconds
			setb	PowerupTimeout			; timer is for transparency
			setb	Kb_TimerRun
			mov	C, TransparentSwitch		; if switched into transparent
			cpl	C				; mode then...
			mov	EA, C				; ...never timeout
			acall	TransparentMode			; Powerup conditions unknown, just
								; keep out of the way

			mov	IE, #8fh			; enable all interrupts
			mov	LEDStateA, #00h			; clear 

MainLoop:		acall	UpdateIndicators		; see what's going on
			acall	ForceLEDUpdate			; show it to the world
			djnz	PollCountdown, MainLoop
			acall	PollAllJoysticks		; poll joysticks every 256
			ajmp	MainLoop			; iterations of above (~80Hz)

; ##############################################################################################

			;	up   down left rght btn3 btn1 btn2 btn4
JoystickCodes:		DB	75h, 72h, 6bh, 74h, 71h, 5ah, 70h, 73h	; cursors
			DB	1bh, 22h, 1ah, 21h, 2ah, 23h, 2bh, 1ch	; bottom left alpha
			DB	42h, 41h, 3ah, 49h, 4ah, 4bh, 4ch, 42h	; bottom middle alpha
			DB	1eh, 1dh, 15h, 24h, 2dh, 26h, 25h, 16h	; top left alpha
			DB	36h, 35h, 2ch, 3ch, 43h, 3dh, 3eh, 2eh	; top middle alpha
			DB	45h, 4dh, 44h, 54h, 5bh, 4eh, 55h, 46h	; top right alpha
			DB	4ch, 4ah, 49h, 59h, 52h, 66h, 5dh, 29h 	; leftover keys
			DB	03h, 0bh, 83h, 0ah, 01h, 09h, 78h, 07h	; function keys

DvorakTransTable:	DB	                         52h, 16h, 17h
			DB	18h, 19h, 4ch, 44h, 1ch, 41h, 1eh, 1fh
			DB	20h, 3bh, 15h, 24h, 49h, 25h, 26h, 27h
			DB	28h, 29h, 42h, 3ch, 35h, 4dh, 2eh, 2fh
			DB	30h, 32h, 22h, 23h, 43h, 2bh, 36h, 37h
			DB	38h, 39h, 3ah, 33h, 34h, 3dh, 3eh, 3fh
			DB	40h, 1dh, 2ch, 21h, 2dh, 45h, 46h, 47h
			DB	48h, 2ah, 1ah, 31h, 1bh, 4bh, 54h, 4fh
			DB	50h, 51h, 4eh, 53h, 4ah, 5bh, 56h, 57h
			DB	58h, 59h, 5ah, 55h

; ##############################################################################################

			END		; stop reading... now!
