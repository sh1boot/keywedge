$NOPAGING
$PAGEWIDTH (132)
$NOMOD
$NODEBUG
$INCLUDE (89C1051.mcu)

QueueEndPtr		EQU	R0
AQueueEndPtr		DATA	AR0

PC_StateIndex		EQU	R6
Kb_StateIndex		EQU	R7

PC_TimerRun		BIT	TR0
Kb_TimerRun		BIT	TR1
PC_IntEnable		BIT	EX0
Kb_IntEnable		BIT	EX1
PC_IntFlag		BIT	IE0
Kb_IntFlag		BIt	IE1

PC_Clock		BIT	P3.2
Kb_Clock		BIT	P3.3
PC_Data			BIT	P3.4
Kb_Data			BIT	P3.5

Js_IncrementStrobe	BIT	P3.0
Js_ResetStrobe		BIT	P3.1
Js_OutputDisable	BIT	P3.7
Js_LEDLatchStrobe	BIT	Js_OutputDisable

Js_IncrementMask	EQU	01h
Js_ResetMask		EQU	02h
PC_ClockMask		EQU	04h
Kb_ClockMask		EQU	08h
PC_DataMask		EQU	10h
Kb_DataMask		EQU	20h
Js_OutputDisableMask	EQU	80h

P3_DefaultState		EQU	0ffh

JoystickPort		DATA	P1

JoyUp			BIT	JoystickPort.0
JoyDown			BIT	JoystickPort.1
JoyLeft			BIT	JoystickPort.2
JoyRight		BIT	JoystickPort.3
Button3			BIT	JoystickPort.4
Button1			BIT	JoystickPort.5
Button2			BIT	JoystickPort.6

NumJoysticks		EQU	2

QueueLength		EQU	18h
QueueThreshold		EQU	10h
MetaCode		EQU	0e0h
Meta2Code		EQU	0e1h
ReleaseCode		EQU	0f0h
ResendCode		EQU	0feh
WinMenuCode		EQU	02fh	; with Meta
WinLeftCode		EQU	01fh	; with Meta
WinRightCode		EQU	027h	; with Meta

HzCrystalFrequency	EQU	24
CrystalDivisor		EQU	12

usClockPhase		EQU	32
usClockPeriod		EQU	(usClockPhase * 2)
usClockPeriodTimeout	EQU	(usClockPeriod * 8)
usResponseTimeout	EQU	20000
usBlockPollTime		EQU	80
usBackChanPollTime	EQU	6000
usBlockHoldTime		EQU	200
usPostByteDelay		EQU	100

ClockPhase		EQU	-(usClockPhase		* HzCrystalFrequency / CrystalDivisor)
ClockPeriod		EQU	-(usClockPeriod		* HzCrystalFrequency / CrystalDivisor)
ClockPeriodTimeout	EQU	-(usClockPeriodTimeout	* HzCrystalFrequency / CrystalDivisor)
BlockPollTime		EQU	-(usBlockPollTime	* HzCrystalFrequency / CrystalDivisor)
BackChanPollTime	EQU	-(usBackChanPollTime	* HzCrystalFrequency / CrystalDivisor)
BlockHoldTime		EQU	-(usBlockHoldTime	* HzCrystalFrequency / CrystalDivisor)
PostByteDelay		EQU	-(usPostByteDelay	* HzCrystalFrequency / CrystalDivisor)
ResponseTimeout		EQU	-(usResponseTimeout	* HzCrystalFrequency / CrystalDivisor)

; things I do often enough to macro but that don't warrant a call or must be
; done quickly

PC_SetupTimer		MACRO	TimeVal
			mov	TL0, #LOW TimeVal
			mov	TH0, #HIGH TimeVal
			setb	PC_TimerRun
			ENDM

Kb_SetupTimer		MACRO	TimeVal
			mov	TL1, #LOW TimeVal
			mov	TH1, #HIGH TimeVal
			setb	Kb_TimerRun
			ENDM

QuickQueue		MACRO	Value
			mov	@QueueEndPtr, Value
			inc	QueueEndPtr
			ENDM

; Instructions I wish existed...

jnbc			MACRO	bitn, label	; jump if no bit else clear
			jnb	bitn, label
			clr	bitn
			ENDM

cje			MACRO	x, y, label	; compare and jump if equal
			cjne	x, y, $+5
			ajmp	label
			ENDM

cmp			MACRO	x, y		; compare and go nowhere
			cjne	x, y, $+3
			ENDM

sub			MACRO	o1, o2		; subtract without carry
			clr	C
			subb	o1, o2
			ENDM
