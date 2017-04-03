; 8051 Keyboard Wedge, by Simon Hosie - 1997,1998,2000
;
; Inserts scancodes into the datastream between a keyboard and PC representing the movements on
; microcomputer joysticks.
;
; Source and listing are intended to be viewed on a 132 column screen.

$INCLUDE (keywedge.inc)

			BSEG	at 0	; Data area containing single bit R/W registers

PC_TransError:		DBIT	1
Kb_TransError:		DBIT	1
Kb_Timeout:		DBIT	1
Kb_Blocking:		DBIT	1	; we're holding the keyboard clock line low, not it
PC_DataParity:		DBIT	1	; parity bit for outgoing data
QueueFull:		DBIT	1	; queue can't take any more data

EndOfBSEG:		DBIT	0	; label to find start of available byte space

; ----------------------------------------------------------------------------------------------------

			DSEG	at 08h
QueueBase:		DS	QueueLength	; scancode queue

			DSEG	at (EndOfBSEG + 7 + 256) / 8

LEDStateA:		DS	1	; generic indicators
LEDStateB:		DS	1	; more generic indicators
DIPSwitchState:		DS	1	; generic switches

Kb_PrefixFlags:		DS	1	; all the prefix flags (for queueing) bunched together
Kb_Meta2PrefixByte:	DS	1	; first code of E1 sequence

Kb_ShiftBuffer:		DS	1	; workspace for transfer
PC_ShiftBuffer:		DS	1

TransTimerMin:		DS	1	; countdown for transparent mode
TransTimerMaj:		DS	1
PollCountdown:		DS	1	; countdown to joystick poll

JoystickState:		DS	NumJoysticks	; state of joystick buttons
KeyboardState:		DS	NumJoysticks	; state of keys that map to joystick buttons

StackBase:		DS	20h	; Stack grows upward from here.

; ----------------------------------------------------------------------------------------------------

TransparentSwitch	BIT	DIPSwitchState.0	; power up in transparent mode
DvorakSwitch		BIT	DIPSwitchState.1	; controls Dvorak keyboard translation
DropWinKeySwitch	BIT	DIPSwitchState.2	; indicates we hate the winmenu key

ShowKeyStateSwitch	BIT	DIPSwitchState.6	; do we want to view the keystate map
IndicatorBankSwitch	BIT	DIPSwitchState.7	; toggles between two display modes

PC_ErrorIndicator	BIT	LEDStateA.0
;PC_TimeoutIndicator	BIT	LEDStateA.1
PC_BlockingIndicator	BIT	LEDStateA.2
PC_TXIndicator		BIT	LEDStateA.3
Kb_ErrorIndicator	BIT	LEDStateA.4
Kb_TimeoutIndicator	BIT	LEDStateA.5
Kb_BlockingIndicator	BIT	LEDStateA.6
Kb_RXIndicator		BIT	LEDStateA.7

; ... take bits 0-4 from Kb_PrefixFlags
QueueOverrunIndicator	BIT	LEDStateB.5
QueueFullIndicator	BIT	LEDStateB.6
QueueNonEmptyIndicator	BIT	LEDStateB.7

Kb_PrefixMeta2Code	BIT	Kb_PrefixFlags.0	; queue E1 before next two codes from keyboard
Kb_GetMeta2PrefixByte	BIT	Kb_PrefixFlags.1	; need the first code of an E1 sequence
Kb_PrefixMetaCode	BIT	Kb_PrefixFlags.2	; queue E0 before next code from keyboard
Kb_PrefixReleaseCode	BIT	Kb_PrefixFlags.3	; queue	F0 before next code from keyboard
Kb_Pre2fixReleaseCode	BIT	Kb_PrefixFlags.4	; say "pre-squared-fix", same as above

; ####################################################################################################
; ####################################################################################################

			; Maybe Intel got it right for some situation with their ISR handling
			; structure, but certainly not this situation.  Give away some ROM space to
			; code readability.

			CSEG	at RESET
ResetPt:		ajmp	Main				; <- Click here to begin

			CSEG	at EXTI0
			ajmp	PC_LowInt

			CSEG	at TIMER0
			ajmp	PC_TimerInt

			CSEG	at EXTI1
			ajmp	Kb_EdgeInt

			CSEG	at TIMER1
			ajmp	Kb_TimerInt

			DB	' * Keywedge 2000-06-29 by Simon Hosie * ', 0

; ####################################################################################################
; ####################################################################################################

			; 'Super Hoopy Data Throughpy' transparency mode....  Attempts to minimise
			; response times by using a state machine.  In this mode nothing else can be
			; done, so only use it to hide from startup conditions and backchannel data or
			; anything else that looks like trouble.

TransparentMode: ;	setb	Js_OutputDisable
;			setb	Js_ResetStrobe
;			clr	Js_ResetStrobe
;			mov	P1, #55h
;			clr	Js_LEDLatchStrobe
;			setb	Js_LEDLatchStrobe
;			mov	P1, #0ffh

State00:		mov	P3, #P3_DefaultState - (0)
			mov	TransTimerMin, #200		; 200 x 10 cycles = 1us
			mov	TransTimerMaj, A
State00L:		jnb	Kb_Clock, State20
			jnb	PC_Clock, State10
			jnb	Kb_Data, State02
			jnb	PC_Data, State01
			djnz	TransTimerMin, State00L
			mov	TransTimerMin, #200
			djnz	TransTimerMaj, State00L
			mov	TransTimerMaj, A
			jb	TransparentSwitch, State00L
			clr	Kb_IntFlag			; Probably got set unintentionally
			ret

State01:		mov	P3, #P3_DefaultState - (Kb_DataMask)
State01L:		jnb	Kb_Clock, State21
			jnb	PC_Clock, State11
			jb	PC_Data, State00
			sjmp	State01L

State02:		mov	P3, #P3_DefaultState - (PC_DataMask)
State02L:		jnb	Kb_Clock, State22
			jnb	PC_Clock, State12
			jb	Kb_Data, State00
			sjmp	State02L

State10:		mov	P3, #P3_DefaultState - (Kb_ClockMask)
State10L:		jb	PC_Clock, State00
			jnb	Kb_Data, State12
			jb	PC_Data, State10L

State11:		mov	P3, #P3_DefaultState - (Kb_ClockMask+Kb_DataMask)
State11L:		jb	PC_Clock, State01
			jb	PC_Data, State10
			sjmp	State11L

State12:		mov	P3, #P3_DefaultState - (Kb_ClockMask+PC_DataMask)
State12L:		jb	PC_Clock, State02
			jb	Kb_Data, State10
			sjmp	State12L

State20:		mov	P3, #P3_DefaultState - (PC_ClockMask)
State20L:		jb	Kb_Clock, State00
			jnb	Kb_Data, State22
			jb	PC_Data, State20L

State21:		mov	P3, #P3_DefaultState - (PC_ClockMask+Kb_DataMask)
State21L:		jb	Kb_Clock, State01
			jb	PC_Data, State20
			sjmp	State21L

State22:		mov	P3, #P3_DefaultState - (PC_ClockMask+PC_DataMask)
State22L:		jb	Kb_Clock, State02
			jb	Kb_Data, State20
			sjmp	State22L

; ####################################################################################################
; ####################################################################################################

			; PC blocking detector.  This may be strobed for as little as 60us to
			; interrupt transmission, so polling it would not be adequate.  Just abandon
			; any transfer in the process.  The rest of the transmission code must be (and
			; is) structured such that it can resume where it left off without data loss.

PC_LowInt:		clr	PC_IntEnable
			setb	PC_Data
			mov	PC_StateIndex, #PC_ClockLowStatePtr-PC_TimerTable
			PC_SetupTimer BlockPollTime
			reti

			; PC clock timer and polling timer.  Just do as the jump table dictates.

PC_TimerInt:		clr	PC_TimerRun
			push	PSW
			push	ACC
			push	DPL
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

			; Keyboard clock input.  Applicable to data going in either direction.

Kb_EdgeInt:		clr	Kb_TimerRun
			clr	Kb_TimerFlag
			clr	Kb_Timeout
			push	PSW
			push	ACC
			push	DPL
			push	DPH
			mov	DPTR, #Kb_EdgeTable
			mov	A, Kb_StateIndex
			inc	Kb_StateIndex
			inc	Kb_StateIndex
			acall	JmpAPlusDPtr
			cje	Kb_StateIndex, #0, Kb_WithoutTimeout
			Kb_SetupTimer ClockPeriodTimeout
Kb_WithoutTimeout:	pop	DPH
			pop	DPL
			pop	ACC
			pop	PSW
			reti

			; Keyboard timeout timer.  Flags transfer as erroneous, resets the state
			; pointer, and gets rid of flags that no longer apply.

Kb_TimerInt:		clr	Kb_TimerRun
			cmp	Kb_StateIndex, #1
			cpl	C
			mov	Kb_TransError, C
			mov	Kb_Timeout, C
			mov	Kb_StateIndex, #0
			mov	Kb_PrefixFlags, #0
			reti

; ####################################################################################################
; ####################################################################################################

			; Jump tables present a convenient way to give a numeric representation to the
			; possible states of each inteface subsection.  This ensures that the
			; controller can't take up conflicting tasks on a single interface and other
			; code can easily determine what is being done at any given time.

JmpAPlusDPtr:		jmp	@A+DPTR				; used in lieu of a relative call

PC_TimerTable:		ajmp	PC_PollData
  PC_ClockLowStatePtr:	ajmp	PC_PollClock
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
PC_TimerTableEnd:

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
Kb_EdgeTableEnd:

; ####################################################################################################

			; Watch the data line from the PC.  If it goes low then it's trying to talk to
			; us.  We want to part of that, so slip into transparent mode.

PC_PollData:		mov	PC_StateIndex, #0
			jnb	PC_Data, PC_PanicStations	; Duck and Cover!
			acall	PeekQueue
			jc	PC_StayIdle
			mov	PC_StateIndex, #PC_SendStatePtr-PC_TimerTable
			mov	PC_ShiftBuffer, A
			mov	C, P
			cpl	C
			mov	PC_DataParity, C
			clr	PC_Data				; prepare start bit
			ajmp	PC_DropClock
PC_StayIdle:		PC_SetupTimer BackChanPollTime
			ret

			; Poll the clock line from the keyboard to see when it's released.  If it is
			; then fall through to checking to see if it was trying to communicate.

PC_PollClock:		mov	PC_StateIndex, #PC_ClockLowStatePtr-PC_TimerTable
			jnb	PC_Clock, PC_KeepPollingClock
			setb	PC_IntEnable
			mov	PC_StateIndex, #0
			PC_SetupTimer PostByteDelay		; for badly written software
			ret
PC_KeepPollingClock:	PC_SetupTimer BlockPollTime
			ret

			; The PC is trying to communicate.  Stay out of the way until the lines
			; settle.  20 milliseconds is the maximum latency for the keyboard response,
			; so wait for that long after the traffic settles to ensure that whatever
			; needed to be done has been done.

PC_PanicStations:	jnb	PC_Clock, PC_PollClock		; clock must still be high
			clr	EA
			mov	A, #22				; 20 milliseconds is maximum latency
			acall	TransparentMode			; for keyboard response
			clr	Kb_TimerRun
			clr	Kb_TimerFlag
			mov     Kb_StateIndex, #0
			mov	Kb_PrefixFlags, #0
			setb	EA
			ajmp	PC_PollData

			; Some self explanatory stuff...

PC_RaiseClock:		setb	PC_Clock
			setb	PC_IntEnable
			PC_SetupTimer ClockPhase
			ret

PC_SendDataBit:		mov	A, PC_ShiftBuffer
			rrc	A
			mov	PC_Data, C
			mov	PC_ShiftBuffer, A
PC_DropClock:		clr	PC_IntEnable
			clr	PC_Clock
			PC_SetupTimer ClockPhase
			ret

PC_SendParityBit:	mov	C, PC_DataParity
			mov	PC_Data, C
			ajmp	PC_DropClock

PC_SendStopBit:		setb	PC_Data
			ajmp	PC_DropClock

PC_FinishSend:		setb	PC_Clock
			setb	PC_IntEnable
			setb	PC_Data				; being cautious
			acall	UnqueueByte
			mov	PC_StateIndex, #0
			PC_SetupTimer PostByteDelay		; for badly written software
			ret

; ----------------------------------------------------------------------------------------------------

			; Some more self explanatory stuff...

Kb_RecvStartBit:	mov	C, Kb_Data			; Start bit should be zero...
			mov	Kb_TransError, C		; ...else it's an error already
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
			orl	C, Kb_TransError		; Stop bit should be '1'
			mov	Kb_TransError, C
			mov	Kb_StateIndex, #0		; Finished, go idle
			jc	Kb_RecvError
			mov	A, Kb_ShiftBuffer
			clr     Kb_Clock			; Block keyboard until
			clr	Kb_IntFlag			; processing done
			acall	Kb_GotByte			; do processing
			jb	Kb_Blocking, Kb_RecvError	; don't unblock if blocking
			setb	Kb_Clock
Kb_RecvError:		ret

; ----------------------------------------------------------------------------------------------------

			; We got a byte from the keyboard.  Rather than attempting to queue prefix
			; bytes as they arrive and having to block the queue until the entire sequence
			; has arrived (requiring another timeout), simply flag the required prefixes
			; and queue them all when there's something to attach them to.

Kb_GotByte:		jbc     Kb_GetMeta2PrefixByte, Kb_GotMeta2PrefixByte
			cjne	A, #MetaCode, Kb_NotMetaCode
			setb	Kb_PrefixMetaCode
			ret
Kb_NotMetaCode:		cjne    A, #Meta2Code, Kb_NotMeta2Code
			setb	Kb_PrefixMeta2Code
			setb	Kb_GetMeta2PrefixByte
			ret
Kb_NotMeta2Code:	cjne	A, #ReleaseCode, Kb_NotAPrefix
			setb	Kb_PrefixReleaseCode
			ret
Kb_GotMeta2PrefixByte:	cjne	A, #ReleaseCode, Kb_NotReleaseCode
			setb	Kb_Pre2fixReleaseCode
			setb	Kb_GetMeta2PrefixByte
			ret
Kb_NotReleaseCode:	mov	Kb_Meta2PrefixByte, A
			ret
Kb_NotAPrefix:
			; Many of the tests don't apply to extended keys, so jump over them

			jb	Kb_PrefixMeta2Code, Kb_Meta2PrefixExists
			jb	Kb_PrefixMetaCode, Kb_MetaPrefixExists

			; Meta codes have all been taken aside at this point, if we're still running
			; then we have a real keycode.  First consider applying Dvorak translation to
			; it.

			jnb	DvorakSwitch, Kb_SkipDvorak
			cmp	A, #15h
			jc	Kb_SkipDvorak
			cmp	A, #5ch
			jnc	Kb_SkipDvorak
			mov	DPTR, #DvorakTransTable - 15h
			movc	A, @A+DPTR
Kb_SkipDvorak:
			; Next see if it needs to be thrown out for conflicting with the state of a
			; joystick.

			mov	C, Kb_PrefixReleaseCode
			acall   Kb_CheckCode
			jc	Kb_Discard
			ajmp	Kb_DontDropWinKey

			; See if we need to discard a WinMenu code.

Kb_MetaPrefixExists:	jnb	DropWinKeySwitch, Kb_DontDropWinKey
			cjne	A, #WinMenuCode, Kb_DontDropWinKey
			ajmp	Kb_Discard

			; Stuff everything in the queue all at once, now.  This is only ever called
			; with the highest interrupt priority, so don't bother blocking other
			; interrupts to avoid prefix fragmentation.

Kb_Meta2PrefixExists:	QuickQueue #Meta2Code
			jnb	Kb_Pre2fixReleaseCode, Kb_NoReleasePre2fix
			QuickQueue #ReleaseCode
Kb_NoReleasePre2fix:	QuickQueue Kb_Meta2PrefixByte

Kb_DontDropWinKey:	jnb	Kb_PrefixMetaCode, Kb_NoMetaPrefix
			QuickQueue #MetaCode
Kb_NoMetaPrefix:	mov	C, Kb_PrefixReleaseCode

			; Queue the actual byte with the official call for full functionality.  If the
			; queue is full (carry is set) then stop the keyboard from sending any more
			; data by forcing the clock line low.

			acall	QueueByte
			mov	Kb_Blocking, C
			cpl	C
			mov	Kb_Clock, C
			clr	Kb_IntFlag
Kb_Discard:		mov	Kb_PrefixFlags, #0
			ret

; ----------------------------------------------------------------------------------------------------

			; See if this key is already held down by a joystick.  I have to write this.

Kb_CheckCode:		push	AR1
			push	AR2
			mov	DPTR, #JoystickCodes - 1	; find the index of this scancode
			mov	R1, #NumJoysticks * 8
			mov	R2, A
KbCC_KeepLooking:	mov	A, R1
			movc	A, @A+DPTR
			xrl	A, R2				; poor man's compare
			jz	KbCC_Success
			djnz	R1, KbCC_KeepLooking
			mov	A, R2				; not found
			pop	AR2
			pop	AR1
			clr	C				; return `no conflict'
			ret

KbCC_Success:		mov	F0, C				; save carry (yes, it's still valid)
			dec	R1				; index from above is biased -- adjust
			push	AR1				; convert into index and mask for bit
			mov	A, R1				; addressing purposes
			anl	A, #07h				; bits 0-2 are index for one joystick
			inc	A				; it's simpler to use a 1-based counter
			mov	R1, A
			clr	A				; convert value in R1 to a bit mask
			setb	C
KbCC_ShiftBit:		rlc	A
			djnz	R1, KbCC_ShiftBit
			mov	R1, A				; save bit mask
			pop	ACC				; get original index...
			anl	A, #0f8h			; ...and divide it by 8
			rr	A
			rr	A
			rr	A
			add	A, #KeyboardState		; make it a useful pointer
			xch	A, R1				; put things in the right place
			jb	F0, KbCC_IsReleaseCode
			clr	C
			orl	A, @R1				; set keyboard state bit
			mov	@R1, A
			ajmp	KbCC_WasPressCode
KbCC_IsReleaseCode:	push	ACC
			cpl	A				; clear keyboard state bit
			anl	A, @R1
			mov	@R1, A
			pop	ACC
			xch	A, R1
			add	A, #JoystickState-KeyboardState
			xch	A, R1
			anl	A, @R1				; check the equiv. joystick state
			mov	C, P				; parity happens to indicate zero/non
KbCC_WasPressCode:	mov	A, R2
			pop	AR2
			pop	AR1
			ret

; ####################################################################################################

QueueByte:		clr	EA
			jnc	QB_PressOnly
			QuickQueue #ReleaseCode
QB_PressOnly:		QuickQueue A
			setb	EA				; ISR relief
			clr	PC_TimerRun
			clr	EA
			cjne	PC_StateIndex, #0, QB_JustQueueIt
			PC_SetupTimer 0ffffh			; get ISR's attention
QB_JustQueueIt:		setb	EA
			setb	PC_TimerRun
			cmp	QueueEndPtr, #QueueBase+QueueThreshold
			cpl	C
			mov	QueueFull, C			; return carry set on full queue
			ret

; ----------------------------------------------------------------------------------------------------

PeekQueue:		cmp	QueueEndPtr, #QueueBase+1	; set carry on nonempty queue
			mov	A, QueueBase			; grab next byte to send
			ret

; ----------------------------------------------------------------------------------------------------

			; Pull the first byte off the queue and move the rest of the queue down.  It
			; appears to start at the wrong end of the queue, but using the xch
			; instruction it's actually faster that way, and the byte to be unqueued pops
			; out at the end and the carry flag is cleared by the cjne.

UnqueueByte:		clr	A
			cmp	QueueEndPtr, #QueueBase+1	; Make sure queue isn't empty
			jc	UB_QueueEmpty
			clr	EA				; mustn't queue anything for a
			dec	QueueEndPtr			; moment or data will be lost
			push	AR1
			mov	R1, AQueueEndPtr
			xch	A, @R1				; grab the last byte queued...
			setb	EA				; ...making it safe to queue more
			ajmp	UB_LoopEntry
UB_Loop:		xch	A, @R1
UB_LoopEntry:		dec	R1
			cjne	R1, #QueueBase-1, UB_Loop
			pop	AR1
UB_QueueEmpty:		mov	F0, C				; preserve carry somewhere
			cmp	QueueEndPtr, #QueueBase+QueueThreshold
			cpl	C
			mov	QueueFull, C			; update queue fullness flag
			jc	UB_DontUnblock			; and unblock if safe to do so
			jbc	Kb_Blocking, UB_UnqueueAndUnblock
UB_DontUnblock:		mov	C, F0				; restore carry
			ret
UB_UnqueueAndUnblock:	clr	Kb_Blocking
			clr	Kb_IntFlag
			setb	Kb_Clock
			mov	C, F0				; restore carry flag
			ret

; ####################################################################################################

			; Cycle through all the joysticks checking their state and queueing data as
			; required.  Also update the DIP switches and LEDs because it's a quick way to
			; get the external index register set up.

PollAllJoysticks:	acall	ForceDIPSwitchUpdate
			mov	R1, #JoystickState
			mov	DPTR, #JoystickCodes
			mov	R2, #NumJoysticks
PAJ_Loop:		push	AR2
			acall	PollJoystick
			pop	AR2
			djnz	R2, PAJ_Loop
			ret

; ----------------------------------------------------------------------------------------------------

PollJoystick:		acall	NextJoystick
			mov	A, JoystickPort			; Get the data

			mov	R2, A
			xch	A, @R1				; Update the current state
			xrl	A, @R1				; Get a list of changes

			push	AR1
			xch	A, R1				; Change to address keyboard state
			add	A, #KeyboardState-JoystickState
			xch	A, R1
			mov	AR3, @R1			; Get keyboard state for equiv. keys
			pop	AR1
			xch	A, R3
			cpl	A
			anl	A, R3				; disable action on keys already down

			; ACC = Bits requiring action
			; R1 = Pointer to joystick state
			; R2 = Current joystick state

			mov	R4, #8				; Count through the eight bits
PJ_Loop:		jnb	ACC.0, PJ_NotThisBit		; See if bit needs action
			jb	QueueFull, PJ_NotThisBit	; Skip if queue is full
			push	ACC
			mov	A, R2				; prepare carry for release code
			mov	C, ACC.0
			cpl	C
			clr	A
			movc	A, @A+DPTR			; get scancode
			acall	QueueByte			; do the queueing
			pop	ACC
			clr	ACC.0				; mark bit as processed
PJ_NotThisBit:		rr	A				; rotate A
			xch	A, R2				; rotate R2
			rr	A
			xch	A, R2
			inc	DPTR				; move to next scancode
			djnz	R4, PJ_Loop			; move to next bit
			xrl	A, @R1
			mov	@R1, A				; reset bits that weren't processed
			inc	R1
			ret

; ####################################################################################################

			; Increment external index register.

NextJoystick:		setb	Js_OutputDisable
			clr	Js_IncrementStrobe
			setb	Js_IncrementStrobe
			clr	Js_OutputDisable
			ret

			; Update LEDs by manipulating the external index register.

ForceLEDUpdate:		setb	Js_OutputDisable
			setb	Js_ResetStrobe
			clr	Js_ResetStrobe
			jnb	ShowKeyStateSwitch, FLU_ShowStatus
;			mov	A, KeyboardState
			mov	A, PC_ShiftBuffer
			jnb	IndicatorBankSwitch, FLU_ShowThis
;			mov	A, JoystickState
			mov	A, Kb_ShiftBuffer
			ajmp	FLU_ShowThis
FLU_ShowStatus:		mov	A, LEDStateA
			jnb	IndicatorBankSwitch, FLU_ShowThis
			mov	A, LEDStateB
FLU_ShowThis:		mov	P1, A
			clr	Js_LEDLatchStrobe
			setb	Js_LEDLatchStrobe
			mov	P1, #0ffh
			ret

			; Update internal representation of DIP switches, as above.

ForceDIPSwitchUpdate:	acall	ForceLEDUpdate
			acall	NextJoystick
			mov	DIPSwitchState, P1
			ret

; ####################################################################################################

			; Just show a whole lot of rubbish on the LEDs for debugging.  This is
			; redundant once the code is deemed functional, but there's no good reason to
			; remove it unless half the ROM goes missing or something weird like that.  If
			; you don't need it then don't mount those components on the PCB, otherwise
			; maybe someone will build an extension module to control disco lights
			; according to keystrokes.

UpdateIndicators:	cmp	PC_StateIndex, #PC_SendStatePtr+2-PC_TimerTable
			cpl	C
			mov	PC_TXIndicator, C
			mov	C, Kb_Timeout
			mov	Kb_TimeoutIndicator, C
			clr	PC_BlockingIndicator
			cjne	PC_StateIndex, #PC_ClockLowStatePtr-PC_TimerTable, UI_PC_NotBlocking
			setb	PC_BlockingIndicator
UI_PC_NotBlocking:	mov	C, PC_TransError
			mov	PC_ErrorIndicator, C

			cmp	Kb_StateIndex, #2
			cpl	C
			mov	Kb_RXIndicator, C
			mov	C, Kb_Blocking
			mov	Kb_BlockingIndicator, C
			mov	C, Kb_TransError
			mov	Kb_ErrorIndicator, C

			mov	A, Kb_PrefixFlags
			mov	LEDStateB, A
			mov	A, QueueEndPtr
			cmp	A, #QueueBase+1
			cpl	C
			mov	QueueNonEmptyIndicator, C
			cmp	A, #QueueBase+QueueThreshold
			cpl	C
			mov	QueueFullIndicator, C
			cmp	A, #QueueBase+QueueLength
			cpl	C
			mov	QueueOverrunIndicator, C
			ret

; ####################################################################################################

Main:			mov	IE, #0				; block ints (in case not usual reset)
			mov	SP, #StackBase - 1		; set up a stack
			mov	P1, #0ffh			; safe P1 output
			mov	P3, #P3_DefaultState		; safe P3 output
			mov	TCON, #04h
			mov	TMOD, #11h			; both timers 16bit
			mov	IP, #04h			; prioritise only the keyboard ISR
			mov	R0, #127			; wipe everything to make sure
			clr	A
ClearRAMLoop:		mov	@R0, A				; misses address 0, but R0 _is_
			djnz	R0, ClearRAMLoop		; address zero, so it's OK.
			mov	QueueEndPtr, #QueueBase		; set up variables
			clr	Js_ResetStrobe			; reset address chip with two _good_
			setb	Js_ResetStrobe			; edges (however the lines were
			clr	Js_ResetStrobe			; waggled before is undefined)
			acall	ForceDIPSwitchUpdate		; Get the transparent mode flag
			mov	A, #200				; Powerup conditions unknown so just
			acall	TransparentMode			; keep out of the way for a while
			mov	IE, #8fh			; Let the ISRs start running
MainLoop:		acall	UpdateIndicators		; see what's going on
			acall	ForceLEDUpdate			; show it to the world
			djnz	PollCountdown, MainLoop
;			mov	PollCountdown, #0		; poll joysticks every 256 iterations
			acall	PollAllJoysticks		; of above.  Around 400Hz
			ajmp	MainLoop

; ####################################################################################################

			;	up   down left rght btn3 btn1 btn2 btn4
JoystickCodes:		DB	75h, 72h, 6bh, 74h, 71h, 5ah, 70h, 73h	; cursors, del, enter, ins, 5
			DB	1bh, 22h, 1ah, 21h, 2ah, 23h, 2bh, 1ch	; sxzcvdfa (bot.lf.alpha)
			DB	33h, 31h, 32h, 3ah, 41h, 3bh, 42h, 34h	; hnrm<jkf (bot.md.alpha)
			DB	1eh, 1dh, 15h, 24h, 2dh, 26h, 25h, 16h	; 2wqer341 (top.lf.alpha)
			DB	36h, 35h, 2ch, 3ch, 43h, 3dh, 3eh, 2eh	; 6ytui785 (top.md.alpha)
			DB	45h, 4dh, 44h, 54h, 5bh, 4eh, 55h, 46h	; 0po{}-=9 (top.rt.alpha)
			DB	4ch, 4ah, 49h, 59h, 52h, 66h, 5dh, 29h 	; ;?>R'B\S (leftovers)
			DB	03h, 0bh, 83h, 0ah, 01h, 09h, 78h, 07h	; function keys

;; an alternative configuration
;JoystickCodes:		DB	75h, 72h, 6bh, 74h, 11h, 5ah, 14h, 12h	; cursors,alt,enter,ctl,lshft
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

; ####################################################################################################

			END		; stop reading here.
