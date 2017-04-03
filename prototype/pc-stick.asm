SCRTCH          = $F9
STICK1          = $FA
STICK2          = $FB
BUF1            = $FC
BUF2            = $FD
QSTART          = $FE
QEND            = $FF
QUEUE           = $0400

NSTIK1          = $DC00
NSTIK2          = $DC01

DEVPRT          = $DD01
DATDIR          = $DD03

BORDER          = $D020
SCREEN          = $D021
TXTCLR          = $0286
CLRSCR          = $E544

KCLKRD          = $80
PDATRD          = $40
KDATRD          = $20
PDATWR          = $04
KDATWR          = $02
PCLKWR          = $01


EXTCOD          = $E0
EX2COD          = $E1
RELCOD          = $F0
RESEND          = $05FC

; ============= BOOTSTRAP =============

* = $0801
            .BYT 8,11,0,0,158
            .BYT '2061'
            .BYT 0,0,0

; =====================================

            LDA #$00
            STA BORDER
            STA SCREEN
            LDA #$0F
            STA TXTCLR
            JSR CLRSCR

            SEI
            LDA SCRTCH
            PHA
            LDA STICK1
            PHA
            LDA DATDIR
            PHA
            LDA #$00
            STA QSTART
            STA QEND
            LDA #$FF
            STA STICK1
            STA STICK2
            LDA #$0F
            STA DATDIR
            JSR POLL
            PLA
            STA DATDIR
            PLA
            STA STICK1
            PLA
            STA SCRTCH
            CLI
            JMP CLRSCR

; =====================================

SNOOZE      PHA
            TXA
            PHA
            LDX #$02
SNZLP       DEX
            BNE SNZLP
            PLA
            TAX
            PLA
            RTS

; -------------------------------------

GETBIT      BIT DEVPRT
            BPL GETBIT
            LDA #KDATRD
            CLC
GBLP        BIT DEVPRT
            BMI GBLP
            BEQ GBZR
            SEC
GBZR        RTS


SNDBIT      LDA DEVPRT
            ORA #PCLKWR
            STA DEVPRT
            AND #255-PDATWR
            BCC SNDBZ
            ORA #PDATWR
SNDBZ       JSR SNOOZE
            STA DEVPRT
            AND #255-PCLKWR
            STA DEVPRT
            JMP SNOOZE

; -------------------------------------

GETBYT      JSR GETBIT
            BCS GETBYT
RCVBYT      LDX #$08
            LDA #$00
            STA BUF2
GBITS       JSR GETBIT
            BCC GBEVEN
            INC BUF2
GBEVEN      ROR BUF1
            DEX
            BNE GBITS
            JSR GETBIT
            LDA BUF2
            ADC #$00
            AND #$01
            BEQ GBERR
            JSR GETBIT
            BCC GBERR2

            INC QEND
            LDX QEND
            LDA BUF1
            STA QUEUE,X
            CMP #RELCOD
            BEQ GETBYT
            CMP #EXTCOD
            BEQ GETBYT
            CMP #EX2COD
            BNE GBEND
            JSR GETBYT
            JMP GETBYT

GBEND       RTS
GBERR       JSR GETBIT
GBERR2      INC BORDER
            LDA #<RESEND
            STA BUF1
            LDA #>RESEND
            STA BUF2
            JSR SEKBYT
            JMP GETBYT


SNDBYT      STA BUF1
            STA BUF2
            LDA #$01
            LDX #$08
PARLP       LSR BUF2
            ADC #$00
            DEX
            BNE PARLP
            ORA #$02
            ASL BUF1
            ROL A
            STA BUF2
            LDX #$0B
SBLP        LSR BUF2
            ROR BUF1
            JSR SNDBIT
            DEX
            BNE SBLP
            RTS

; =====================================

GEPBIT      LDA DEVPRT
            ORA #PCLKWR
            STA DEVPRT
            JSR SNOOZE
            LDA DEVPRT
            AND #255-PCLKWR
            STA DEVPRT
            JSR SNOOZE
            AND #PDATRD
            CMP #PDATRD
            RTS


SEKBIT      LDA DEVPRT
            BMI SEKBIT
            AND #255-KDATWR
            BCC SKLP
            ORA #KDATWR
SKLP        BIT DEVPRT
            BPL SKLP
            STA DEVPRT
            RTS

; -------------------------------------

GEPBYT      JSR SNOOZE
            JSR SNOOZE
            LDA DEVPRT
            AND #255-PCLKWR
            STA DEVPRT

GPWT1       BIT DEVPRT
            BVC GPWT1
            ORA #PCLKWR
            STA DEVPRT
GPWT2       JSR SNOOZE
            BIT DEVPRT
            BVS GPWT2
            AND #255-PCLKWR
            STA DEVPRT
            JSR SNOOZE
            LDX #$08
            LDA #$00
            STA BUF2
GPBITS      JSR GEPBIT
            BCC GPEVEN
            INC BUF2
GPEVEN      ROR BUF1
            DEX
            BNE GPBITS
            LDA DEVPRT
            ORA #PCLKWR
            STA DEVPRT
            JSR SNOOZE
            LDA DEVPRT
            AND #255-PDATWR
            STA DEVPRT
            AND #PDATRD
            CMP #PDATRD
            LDA BUF2
            ADC #$00
            AND #$01
            STA BUF2
            JSR SNOOZE
            JSR SNOOZE
            LDA DEVPRT
            ORA #PDATWR
            STA DEVPRT
            LDA BUF2
            BNE GPERR
            LDA BUF1
            RTS
GPERR       LDA #400
            RTS


SEKBYT      STA BUF1
            STA BUF2
            LDA #$01
            LDX #$08
SKPRLP      LSR BUF2
            ADC #$00
            DEX
            BNE SKPRLP
            ORA #$02
            ASL BUF1
            ROL A
            STA BUF2
            LDA DEVPRT
            AND #255-KDATWR
            STA DEVPRT
SKWAIT      BIT DEVPRT
            BMI SKWAIT

SKLP0A      LDA DEVPRT
            BMI SKLP0A
            AND #255-KDATWR
            LSR BUF1
            BCC SKLP0B
            ORA #KDATWR
SKLP0B      BIT DEVPRT
            BPL SKLP0B
            STA DEVPRT

SKLP1A      LDA DEVPRT
            BMI SKLP1A
            AND #255-KDATWR
            LSR BUF1
            BCC SKLP1B
            ORA #KDATWR
SKLP1B      BIT DEVPRT
            BPL SKLP1B
            STA DEVPRT

SKLP2A      LDA DEVPRT
            BMI SKLP2A
            AND #255-KDATWR
            LSR BUF1
            BCC SKLP2B
            ORA #KDATWR
SKLP2B      BIT DEVPRT
            BPL SKLP2B
            STA DEVPRT

SKLP3A      LDA DEVPRT
            BMI SKLP3A
            AND #255-KDATWR
            LSR BUF1
            BCC SKLP3B
            ORA #KDATWR
SKLP3B      BIT DEVPRT
            BPL SKLP3B
            STA DEVPRT

SKLP4A      LDA DEVPRT
            BMI SKLP4A
            AND #255-KDATWR
            LSR BUF1
            BCC SKLP4B
            ORA #KDATWR
SKLP0B      BIT DEVPRT
            BPL SKLP4B
            STA DEVPRT

SKLP5A      LDA DEVPRT
            BMI SKLP5A
            AND #255-KDATWR
            LSR BUF1
            BCC SKLP5B
            ORA #KDATWR
SKLP5B      BIT DEVPRT
            BPL SKLP5B
            STA DEVPRT

SKLP6A      LDA DEVPRT
            BMI SKLP6A
            AND #255-KDATWR
            LSR BUF1
            BCC SKLP6B
            ORA #KDATWR
SKLP6B      BIT DEVPRT
            BPL SKLP6B
            STA DEVPRT

SKLP7A      LDA DEVPRT
            BMI SKLP7A
            AND #255-KDATWR
            LSR BUF1
            BCC SKLP7B
            ORA #KDATWR
SKLP7B      BIT DEVPRT
            BPL SKLP7B
            STA DEVPRT

SKLP8A      LDA DEVPRT
            BMI SKLP8A
            AND #255-KDATWR
            LSR BUF1
            BCC SKLP8B
            ORA #KDATWR
SKLP8B      BIT DEVPRT
            BPL SKLP8B
            STA DEVPRT

SKLP9A      LDA DEVPRT
            BMI SKLP9A
            AND #255-KDATWR
            LSR BUF1
            BCC SKLP9B
            ORA #KDATWR
SKLP9B      BIT DEVPRT
            BPL SKLP9B
            STA DEVPRT

SKLPAA      LDA DEVPRT
            BMI SKLPAA
            AND #255-KDATWR
            LSR BUF1
            BCC SKLPAB
            ORA #KDATWR
SKLPAB      BIT DEVPRT
            BPL SKLPAB
            STA DEVPRT

            RTS

; =====================================

ADDTOQ      INC QEND
            LDY QEND
            STA QUEUE,Y
            RTS

FLUSH       LDY QSTART
            CPY QEND
            BEQ FLDONE
FLLP        INY
            LDA QUEUE,Y
            JSR SNDBYT
            CPY QEND
            BNE FLLP
            STY QSTART
FLDONE      RTS

; =====================================


DOKBD       BIT DEVPRT
            BMI DUNKBD
DOKBDF      JMP RCVBYT
DUNKBD      RTS

DOJOY       LDA NSTIK1
            EOR STICK1
            BEQ SKSTK1
            PHA
            EOR STICK1
            STA STICK1
            STA SCRTCH
            PLA
            LDX #$05
ST1LP       LSR A
            BCC ST1SK1
            PHA
            LSR SCRTCH
            BCC ST1SK2
            LDA #$F0
            JSR ADDTOQ
ST1SK2      LDA TABLE1-1,X
            JSR ADDTOQ
            PLA
            .BYT $2C
ST1SK1      LSR SCRTCH
            DEX
            BNE ST1LP
SKSTK1      RTS

; =====================================

POLL        BIT DEVPRT
            BMI P2
P1          JSR RCVBYT
            JSR FLUSH
P2          LDA NSTIK1
            BIT DEVPRT
            BPL P1
            EOR STICK1
            BNE J1
            BIT DEVPRT
            BMI P4
P3          JSR RCVBYT
            JSR FLUSH
P4          LDA $DC01
            BIT DEVPRT
            BPL P3
            CMP #$FF
            BEQ POLL
            RTS

J1          JSR DOJOY
            JSR FLUSH
            JMP POLL

; =====================================

TABLE1      .BYT $5A,$74,$6B,$72,$75
TABLE2      .BYT $29,$23,$1C,$22,$1D

