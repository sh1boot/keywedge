; 8051 Keyboard Wedge, by Simon Hosie - 1997,1998,2000
;
;	Inserts scancodes into the datastream between a keyboard and PC
;	representing the movements on outdated microcomputer joysticks.
;
;	Source code is meant to be viewed on a 132 column screen.

$INCLUDE (keywedge.inc)

			BSEG	at 0	; Data area containing single bit R/W registers

PC_TransError:		DBIT	1	; send resend when dust settles
Kb_TransError:		DBIT	1	; send resend when dust settles

Kb_DeferTimeout:	DBIT	1	; don't set usual timeout period
Kb_SendSetup:		DBIT	1	; timer interrupt means to start sending data to keyboard
Kb_Blocking:		DBIT	1	; we're holding the keyboard clock line low, not it
PC_SoftBlock:		DBIT	1	; PC has disabled scanning for some reason

Kb_ToRespondNow:	DBIT	1	; next byte from keyboard should shortcut queue
PC_ByteFromQueue:	DBIT	1	; unqueue this byte when sent OK

Kb_PrefixMeta2Code:	DBIT	1	; queue E1 in front of next two codes from keyboard
Kb_PrefixMetaCode:	DBIT	1	; queue E0 in front of next code from keyboard
Kb_PrefixReleaseCode:	DBIT	1	; queue	F0 in front of next code from keyboard
Kb_Pre2fixReleaseCode:	DBIT	1	; say "pre-squared-fix", same as above
Kb_GetMeta2PrefixByte:	DBIT	1	; need the first code of an E1 sequence

PowerupTimeout:		DBIT	1	; interrupt ocurred for powerup delay

QueueFull:		DBIT	1	; queue can't take any more data

EndOfBSEG:		DBIT	0	; label to find start of available byte space

; ----------------------------------------------------------------------------------------------

			DSEG	at 08h
QueueBase:		DS	QueueLength	; scancode queue

			DSEG	at (EndOfBSEG + 7 + 256) / 8

LEDStateA:		DS	1	; generic indicators
LEDStateB:		DS	1	; more generic indicators
DIPSwitchState:		DS	1	; generic switches

Kb_Meta2PrefixByte:	DS	1	; first code of E1 sequence

Kb_ShiftBuffer:		DS	1	; workspace for transfer
PC_ShiftBuffer:		DS	1

PC_ByteToSend:		DS	1	; good copy of outgoing data
Kb_ByteToSend:		DS	1

PC_LastByteSent:	DS	1	; for resend requests
Kb_LastByteSent:	DS	1

PowerupCountdown:	DS	1	; extension on timer 1 for powerup delay
PollCountdown:		DS	1	; countdown to joystick poll

KeyboardState:		DS	NumJoysticks	; state of joystick buttons
JoystickState:		DS	NumJoysticks	; state of keys that map to joystick buttons

StackBase:		DS	20h	; put the stack here

; ----------------------------------------------------------------------------------------------

TransparentSwitch	BIT	DIPSwitchState.0	; Power up in braindead mode
DvorakSwitch		BIT	DIPSwitchState.1	; controls Dvorak keyboard translation
DropWinkeySwitch	BIT	DIPSwitchState.2	; unused, but would be a nice feature
IndicatorBankSwitch	BIT	DIPSwitchState.7	; toggles between two display modes

PC_TXIndicator		BIT	LEDStateA.0
PC_RXIndicator		BIT	LEDStateA.1
PC_BlockingIndicator	BIT	LEDStateA.2
PC_ErrorIndicator	BIT	LEDStateA.3
Kb_TXIndicator		BIT	LEDStateA.4
Kb_RXIndicator		BIT	LEDStateA.5
Kb_BlockingIndicator	BIT	LEDStateA.6
Kb_ErrorIndicator	BIT	LEDStateA.7

MetaPrefixIndicator	BIT	LEDStateB.0
Meta2PrefixIndicator	BIT	LEDStateB.1
ReleasePrefixIndicator	BIT	LEDStateB.2
RespondNowIndicator	BIT	LEDStateB.3
QueueOverrunIndicator	BIT	LEDStateB.6
QueueFullIndicator	BIT	LEDStateB.7

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
; ##############################################################################################

; 'Super Hoopy Data Throughpy' transparency mode.
;	State machine to minimise response times to changes in lines, useful
;	for situations that can't be resolved by general simulation such as
;	unexpected protocol extensions or strange powerup conditions.

;	Each state begins by setting outputs to match inputs, then waiting
;	for an input to change and branching to the new state which will in
;	turn reconfigure outputs to fit and wait for the next change. 
;	Extremely inefficient in terms of ROM usage, but reliable.

TransparentMode:
State00:		mov	P3, #P3_DefaultState - (0)
			mov	TH1, #00
State00L:		jnb	Kb_Clock, State20
			jnb	PC_Clock, State10
			jnb	Kb_Data, State02
			jb	PC_Data, State00L

State01:		mov	P3, #P3_DefaultState - (Kb_DataMask)
			mov	TH1, #00
State01L:		jnb	Kb_Clock, State21
			jnb	PC_Clock, State11
			jb	PC_Data, State00
			sjmp	State01L

State02:		mov	P3, #P3_DefaultState - (PC_DataMask)
			mov	TH1, #00
State02L:		jnb	Kb_Clock, State22
			jnb	PC_Clock, State12
			jb	Kb_Data, State00
			sjmp	State02L

State10:		mov	P3, #P3_DefaultState - (Kb_ClockMask)
			mov	TH1, #00
State10L:		jb	PC_Clock, State00
			jnb	Kb_Data, State12
			jb	PC_Data, State10L

State11:		mov	P3, #P3_DefaultState - (Kb_ClockMask+Kb_DataMask)
			mov	TH1, #00
State11L:		jb	PC_Clock, State01
			jb	PC_Data, State10
			sjmp	State11L

State12:		mov	P3, #P3_DefaultState - (Kb_ClockMask+PC_DataMask)
			mov	TH1, #00
State12L:		jb	PC_Clock, State02
			jb	Kb_Data, State10
			sjmp	State12L

State20:		mov	P3, #P3_DefaultState - (PC_ClockMask)
			mov	TH1, #00
State20L:		jb	Kb_Clock, State00
			jnb	Kb_Data, State22
			jb	PC_Data, State20L

State21:		mov	P3, #P3_DefaultState - (PC_ClockMask+Kb_DataMask)
			mov	TH1, #00
State21L:		jb	Kb_Clock, State01
			jb	PC_Data, State20
			sjmp	State21L

State22:		mov	P3, #P3_DefaultState - (PC_ClockMask+PC_DataMask)
			mov	TH1, #00
State22L:		jb	Kb_Clock, State02
			jb	Kb_Data, State20
			sjmp	State22L

; ##############################################################################################
; ##############################################################################################

JmpAPlusDPtr:		jmp	@A+DPTR				; used in lieu of a relative call

PC_TimerTable:		nop
			nop
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

  PC_LowClockStatePtr:	ajmp	PC_CheckLowClock

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
; If the Kb_SendSetup bit is set then we've been holding the clock and data
; lines low to indicate to the keyboard that we want to send data.  That
; time is up, so begin the transfer.
;
; Otherwise something has gone wrong.  Flag the transfer as bad.

Kb_TimerInt:		jb	PowerupTimeout, PowerupInt
			clr	Kb_TimerRun
			jbc	Kb_SendSetup, Kb_StartTransfer
			clr	Kb_ToRespondNow
			push	PSW
			cjne	Kb_StateIndex, #0, Kb_TransTimeout
;			clr	Kb_ToRespondNow
			pop	PSW
			reti
Kb_TransTimeout:	setb	Kb_TransError
			mov	Kb_StateIndex, #0
Kb_NoTransTimeout:	pop	PSW
			reti
Kb_StartTransfer:	clr	Kb_IntFlag
			setb	Kb_Clock
			setb	Kb_IntEnable
			Kb_SetupTimer ClockPeriodTimeout
			reti

PowerupInt:		djnz    PowerupCountdown, PowerupDontFinish
			inc	PowerupCountdown		; so it always dec's to zero
			clr	PowerupTimeout
			clr	Kb_TimerRun
			dec	SP				; break out of current function
			dec	SP				; (known to be TransparentMode)
PowerupDontFinish:	reti

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
			rrc	A
			mov	PC_Data, C
			mov	PC_ShiftBuffer, A
			ajmp	PC_DropClock

PC_SendParityBit:	clr	A
			xch	A, PC_ByteToSend
			mov	C, P
			cpl	C
			mov	PC_Data, C
			cje	A, #ResendCode, PC_DropClock	; don't log RESEND for resending
			mov	PC_LastByteSent, A
			ajmp	PC_DropClock

PC_SendStopBit:		setb	PC_Data
			ajmp	PC_DropClock

PC_FinishSend:		setb	PC_Clock
			setb	PC_IntEnable
			setb	PC_Data				; being cautious
			acall	PC_SentByte
			PC_SetupTimer PostByteDelay		; for badly written software
			ret

PC_SendNextOrIdle:	mov	PC_StateIndex, #0
			acall	PeekQueue
			setb	PC_ByteFromQueue
			jc	PC_GoIdle
			ajmp	PC_StartSend
PC_GoIdle:		ret

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
			mov	A, #ResendCode
			ajmp	Kb_StartSend
Kb_RecvOK:		mov	A, Kb_ShiftBuffer
			cjne	A, #ResendCode, Kb_NotResendReq
			mov	A, Kb_LastByteSent
			ajmp	Kb_StartSend
Kb_NotResendReq:	clr     Kb_Clock
			acall	Kb_GotByte
			setb	Kb_Clock
			ret

; ----------------------------------------------------------------------------------------------

Kb_SendDataBit:		mov	A, Kb_ShiftBuffer
			rrc	A
			mov	Kb_Data, C
			mov	Kb_ShiftBuffer, A
			ret

Kb_SendParityBit:	clr	A
			xch	A, Kb_ByteToSend
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

; We sent a byte to the PC successfully.  If it came from the queue then get
; rid of it.

PC_SentByte:		jnbc	PC_ByteFromQueue, PCSB_DontUnqueue
			ajmp	UnqueueByte
PCSB_DontUnqueue:	ret

; ----------------------------------------------------------------------------------------------

; We got a byte from the keyboard.  If we were expecting a response to a
; command then check that it's valid and send it on if it is, if not then
; keep waiting until timeout.  Otherwise analyse and/or queue it.

Kb_GotByte:		jnb	Kb_ToRespondNow, Kb_DontRespondNow
			jnb	ACC.7, Kb_NotResponseCode	; scancodes aren't responses
			cje	A, #83h, Kb_NotResponseCode	; F7 is a confused key
			cje	A, #MetaCode, Kb_NotResponseCode
			cje	A, #Meta2Code, Kb_NotResponseCode
			cje	A, #ReleaseCode, Kb_NotResponseCode
			clr	Kb_ToRespondNow			; we got something we can use as
			ajmp	PC_StartSend			; a response
Kb_NotResponseCode:	Kb_SetupTimer ResponseTimeout

Kb_DontRespondNow:	jbc     Kb_GetMeta2PrefixByte, Kb_GotMeta2PrefixByte

			cjne	A, #MetaCode, Kb_NotMetaCode
			setb	Kb_PrefixMetaCode
			ret
Kb_NotMetaCode:		cjne    A, #Meta2Code, Kb_NotMeta2Code
			setb	Kb_PrefixMeta2Code
			setb	Kb_GetMeta2PrefixByte
			ret
Kb_NotMeta2Code:	cjne	A, #ReleaseCode, Kb_NotReleaseCode
			setb	Kb_PrefixReleaseCode
			ret

Kb_NotReleaseCode:	jnb	DvorakSwitch, Kb_DontTranslateIt
			cmp	A, #15h
			jc	Kb_DontTranslateIt
			cmp	A, #5ch
			jnc	Kb_DontTranslateIt
			mov	DPTR, #DvorakTransTable - 15h
			movc	A, @A+DPTR

	; ...input translation done, now try to output the thing...

Kb_DontTranslateIt:	jb      Kb_PrefixMeta2Code, Kb_DontDiscard
			jb      Kb_PrefixMetaCode, Kb_DontDiscard
			acall   Kb_CheckCode
			jnc	Kb_DontDiscard
			clr	Kb_PrefixReleaseCode
			ret

Kb_DontDiscard:		jnbc	Kb_PrefixMeta2Code, Kb_NoMeta2Prefix
			QuickQueue #Meta2Code
			jnbc	Kb_Pre2fixReleaseCode, Kb_NoReleasePre2fix
			QuickQueue #ReleaseCode
Kb_NoReleasePre2fix:	QuickQueue Kb_Meta2PrefixByte

Kb_NoMeta2Prefix:	jnbc	Kb_PrefixMetaCode, Kb_NoMetaPrefix
			QuickQueue #MetaCode
Kb_NoMetaPrefix:	mov	C, Kb_PrefixReleaseCode
			clr	Kb_PrefixReleaseCode
			acall	QueueByte
			jnc	Kb_DontStartBlocking
			setb	Kb_Blocking
			clr	Kb_IntEnable
			clr	Kb_Clock
Kb_DontStartBlocking:	ret

Kb_GotMeta2PrefixByte:	cjne	A, #ReleaseCode, Kb_NotReleaseCode_2
			setb	Kb_Pre2fixReleaseCode
			setb	Kb_GetMeta2PrefixByte
			ret
Kb_NotReleaseCode_2:	mov	Kb_Meta2PrefixByte, A
			ret

; ----------------------------------------------------------------------------------------------

; We send a byte to the keyboard successfully.  Expect a reply.

Kb_SentByte:		Kb_SetupTimer ResponseTimeout
			setb	Kb_ToRespondNow
			ret

; ==============================================================================================

PC_StartSend:		cjne    PC_StateIndex, #0, PCSS_ForgetSend
			clr	PC_IntEnable
			clr	PC_Data
			clr	PC_Clock
			mov	PC_ShiftBuffer, A
			mov	PC_ByteToSend, A
			mov	PC_StateIndex, #PC_SendStatePtr - PC_TimerTable
			PC_SetupTimer ClockPhase
PCSS_ForgetSend:	ret

; ----------------------------------------------------------------------------------------------

Kb_StartSend:		clr	Kb_IntEnable
			clr	Kb_Clock
			clr	Kb_Data
			mov	Kb_ShiftBuffer, A
			mov	Kb_ByteToSend, A
			mov	Kb_StateIndex, #Kb_SendStatePtr - Kb_EdgeTable
			setb	Kb_SendSetup
			Kb_SetupTimer BlockHoldTime
			ret

; ##############################################################################################

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
			mov	C, Kb_PrefixReleaseCode
			cpl	C
			acall	CarryToBitN
			pop	AR1
			mov	@R1, A
			pop	ACC
			jb	Kb_PrefixReleaseCode, KbCC_ConsiderBlocking
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

; ##############################################################################################

QueueByte:		clr	EA
			jnc	QB_PressOnly
			QuickQueue #ReleaseCode
QB_PressOnly:		QuickQueue A
			setb	EA
			cjne	PC_StateIndex, #0, QB_JustQueueIt
;			jb	Kb_ToRespondNow, QB_JustQueueIt
			push	ACC
			acall	PeekQueue
			setb	PC_ByteFromQueue
			acall	PC_StartSend
			pop	ACC
QB_JustQueueIt:		cmp	QueueEndPtr, #QueueBase+QueueThreshold
			cpl	C
			mov	QueueFull, C
			ret

; ----------------------------------------------------------------------------------------------

PeekQueue:		cmp	QueueEndPtr, #QueueBase+1
			mov	A, QueueBase
			ret

; ----------------------------------------------------------------------------------------------

UnqueueByte:		clr	A
			cmp	QueueEndPtr, #QueueBase+1
			jc	UB_QueueEmpty
			clr	EA
			dec	QueueEndPtr
			push	AR1
			mov	R1, AQueueEndPtr
			xch	A, @R1
			setb	EA
			ajmp	UB_LoopEntry
UB_Loop:		xch	A, @R1
UB_LoopEntry:		dec	R1
			cjne	R1, #QueueBase-1, UB_Loop
			pop	AR1
UB_QueueEmpty:		mov	F0, C
			cmp	QueueEndPtr, #QueueBase+QueueThreshold
			cpl	C
			mov	QueueFull, C
			jc	UB_DontUnblock
			jbc	Kb_Blocking, UB_UnqueueAndUnblock
UB_DontUnblock:		mov	C, F0
			ret
UB_UnqueueAndUnblock:	clr	Kb_Blocking
			clr	Kb_IntFlag
			setb	Kb_Clock
			setb	Kb_IntEnable
			mov	C, F0
			ret

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
			cpl	C
			clr	A
			movc	A, @A+DPTR
			acall	QueueByte
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

			mov	C, Kb_PrefixMetaCode
			mov	MetaPrefixIndicator, C
			mov	C, Kb_PrefixMeta2Code
			mov	Meta2PrefixIndicator, C
			mov	C, Kb_PrefixReleaseCode
			mov	ReleasePrefixIndicator, C
			mov	C, Kb_ToRespondNow
			mov	RespondNowIndicator, C
			ret

; ##############################################################################################

Main:			mov	IE, #0
			mov	SP, #StackBase - 1		; set up general operating
			mov	P1, #0ffh			; parameters
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

			clr	Js_ResetStrobe
			setb	Js_ResetStrobe			; reset address chip with two
			clr	Js_ResetStrobe			; _good_ edges (however the
								; lines were waggled before is
								; undefined)

			mov	IE, #08h			; prepare timer 1 only

			mov	LEDStateA, #033h		; show that we're in
			acall	ForceDIPSwitchUpdate		; transparent mode

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
JoystickCodes:		DB	75h, 72h, 6bh, 74h, 71h, 5ah, 70h, 73h	; cursors,del,enter,ins,5
			DB	1bh, 22h, 1ah, 21h, 2ah, 23h, 2bh, 1ch	; sxzcvdfa (bot.lf.alpha)
			DB	33h, 31h, 32h, 3ah, 41h, 3bh, 42h, 34h	; hnrm<jkf (bot.md.alpha)
			DB	1eh, 1dh, 15h, 24h, 2dh, 26h, 25h, 16h	; 2wqer341 (top.lf.alpha)
			DB	36h, 35h, 2ch, 3ch, 43h, 3dh, 3eh, 2eh	; 6ytui785 (top.md.alpha)
			DB	45h, 4dh, 44h, 54h, 5bh, 4eh, 55h, 46h	; 0po{}-=9 (top.rt.alpha)
			DB	4ch, 4ah, 49h, 59h, 52h, 66h, 5dh, 29h 	; ;?>R'B\S (leftovers)
			DB	03h, 0bh, 83h, 0ah, 01h, 09h, 78h, 07h	; function keys

;JoystickCodes:		DB	75h, 72h, 6bh, 74h, 11h, 5ah, 14h, 12h	; cursors,alt,enter,ctl,lsh
;			DB	7dh, 69h, 6ch, 7ah, 79h, 70h, 71h, 7bh	; dcursors,plus,ins,del,minus
;			DB	1bh, 22h, 1ah, 21h, 2ah, 23h, 2bh, 1ch	; sxzcvdfa (bot.lf.alpha)
;			DB	33h, 31h, 32h, 3ah, 41h, 3bh, 42h, 34h	; hnrm<jkf (bot.md.alpha)
;			DB	1eh, 1dh, 15h, 24h, 2dh, 26h, 25h, 16h	; 2wqer341 (top.lf.alpha)
;			DB	36h, 35h, 2ch, 3ch, 43h, 3dh, 3eh, 2eh	; 6ytui785 (top.md.alpha)
;			DB	45h, 4dh, 44h, 54h, 5bh, 4eh, 55h, 46h	; 0po{}-=9 (top.rt.alpha)
;			DB	4ch, 4ah, 49h, 59h, 52h, 66h, 5dh, 29h 	; ;?>R'B\S (leftovers)



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
