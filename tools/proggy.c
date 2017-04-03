#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <getopt.h>
#include <stdarg.h>
#include <sys/io.h>

#define BASE_ADDR						0x3bc
#define CTRL_PORT						(BASE_ADDR)
#define STAT_PORT						(BASE_ADDR + 1)
#define POWR_PORT						(BASE_ADDR + 2)

#define ERR_COMPAREFAIL					13
#define ERR_NOTBLANK					12
#define ERR_BADID						11
#define ERR_NOPROGRAMMER				10
#define ERR_INTERNAL					9
#define	ERR_EXTERNAL					2
#define ERR_USER						1

#define ID_AT89C1051					0x1e11
#define ID_AT89C2051					0x1e21

#define TIME_VppSETTLE					1000000
#define TIME_VppSETUP					11000
#define TIME_VppHOLD					11000
#define TIME_INCWIDTH					220
#define TIME_READYWAIT					1100
#define TIME_WRITECYCLE					1100
#define TIME_PROTECTCYCLE				1100
#define TIME_ERASECYCLE					22000
#define TIME_DATAHOLD					1100
#define TIME_ADDRHOLD					1100

#define POW_ON							2
#define POW_12V							1
#define ST_BUSY							32
#define ST_DIN							128
#define CTL_PROG						2
#define CTL_INC							4
#define CTL_DOUT						8
#define CTL_ENAB						32
#define CTL_STROBE						64
#define CTL_CLOCK						128
#define CTL_P33							16
#define CTL_P34							32
#define CTL_P35							1

#define MD_MASK							(CTL_P33 | CTL_P34 | CTL_P35)
#define MD_ID							(0       | 0       | 0      )
#define MD_READ							(0       | 0       | CTL_P35)
#define MD_WRITE						(0       | CTL_P34 | CTL_P35)
#define MD_ERASE						(CTL_P33 | 0       | 0      )
#define MD_READINHIBIT					(CTL_P33 | CTL_P34 | 0      )
#define MD_WRITEINHIBIT					(CTL_P33 | CTL_P34 | CTL_P35)


__extension__ typedef unsigned long long verylong;

static verylong		tscreference;
static int			giveup				= 0,
					beverbose			= 0,
					bequiet				= 0;
static unsigned char controlword		= 0;

#define NANOSEC_DIVIDER					5
#define sleepref()						(tscreference = gettsc())
#define nspan(t)						xsleep((t) / NANOSEC_DIVIDER)
#define nsleep(t)						(sleepref(), nspan(t))

static __inline__ verylong gettsc(void) { unsigned a, d; __asm__ __volatile__ (".byte 0x0f, 0x31" :"=a" (a), "=d" (d)); return ((verylong)d << 32) + a; }
static __inline__ void xsleep(verylong d) { d += tscreference; while (d >= gettsc()) ; }

static __inline__ void outp(unsigned short port, unsigned char value) { __asm__ __volatile__ ("out" "b" " %" "b" "0,%"  "w" "1" : : "a" (value), "Nd" (port)); }
static __inline__ unsigned char inp(unsigned short port) { unsigned char _v; __asm__ __volatile__ ("in" "b" " %" "w" "1,%" "" "0" : "=a" (_v) : "Nd" (port) ); return _v; }

int busystatus(void) { return (inp(STAT_PORT) & ST_BUSY) == 0; } 
int getdata(void) { return (inp(STAT_PORT) & ST_DIN) == 0; } 
void progvoltage(int V) { if (V < 5) outp(BASE_ADDR + 2, 0); else if (V < 12) outp(BASE_ADDR + 2, POW_ON); else outp(BASE_ADDR + 2, POW_ON | POW_12V); }
void writecontrolword(void) { outp(CTRL_PORT, controlword); }
void setdata(int b) { if (b) controlword |= CTL_DOUT; else controlword &= ~CTL_DOUT; }
void setclock(int b) { if (b) controlword |= CTL_CLOCK; else controlword &= ~CTL_CLOCK; }
void setstrobe(int b) { if (b) controlword |= CTL_STROBE; else controlword &= ~CTL_STROBE; }
void setenable(int b) { if (b) controlword |= CTL_ENAB; else controlword &= ~CTL_ENAB; }
void setincrement(int b) { if (b) controlword |= CTL_INC; else controlword &= ~CTL_INC; }
void setprog(int b) { if (b) controlword |= CTL_PROG; else controlword &= ~CTL_PROG; }
void setmodebits(int mode) { controlword = (controlword & ~MD_MASK) | mode; }
void close_io(void) { outp(CTRL_PORT, 0); outp(POWR_PORT, 0); }
void sighandler(int signal) { giveup = 1; }

void setup_io(void)
{
	if (ioperm(BASE_ADDR, 3, 1) < 0)
		perror("Access to parallel port denied"), exit(ERR_EXTERNAL);

	controlword = 0;
	outp(CTRL_PORT, 0);
	outp(POWR_PORT, 0);

	signal(SIGINT, sighandler);

	atexit(close_io);
}

void sendbyte(unsigned char value)
{
	int					i;
	
	writecontrolword();
	for (i = 0; i < 8; i++)
	{
		setclock(0);
		setdata(value & 128);
		writecontrolword();
		setclock(1);
		writecontrolword();
		value <<= 1;
	}
	setclock(0);
	setstrobe(1), writecontrolword();
	setstrobe(0), writecontrolword();
}

unsigned char getbyte(void)
{
	unsigned char		value = 0;
	int					i;

	setclock(0);
	setstrobe(1), writecontrolword();
	setstrobe(0), writecontrolword();

	for (i = 0; i < 8; i++)
	{
		value = (value << 1) | getdata();
		setclock(1);
		writecontrolword();
		setclock(0);
		writecontrolword();
	}
	return value;
}

void setchipmode(int mode, int V)
{
	progvoltage(0), nsleep(TIME_VppSETTLE);
	setmodebits(mode), setprog(1), setincrement(0), writecontrolword();
	progvoltage(V), nsleep(TIME_VppSETTLE);
}

void incrementaddress(void)
{
	setincrement(1), writecontrolword();
	nsleep(TIME_INCWIDTH);
	setincrement(0), writecontrolword();
}

void progstrobe(verylong delay)
{
	setprog(0), writecontrolword();
	nsleep(delay);
	setprog(1), writecontrolword();
}

int unitpresent(void)
{
	int					i;

	setchipmode(MD_READ, 5);
	setenable(1), writecontrolword();
	for (i = 1; i < 256; i += 37)
	{
		sendbyte(i);
		if (getbyte() != i)
		{
			return 0;
			setenable(0), writecontrolword();
		}
	}
	setenable(0), writecontrolword();
	return 1;
}

void chiperase(void)
{
	setchipmode(MD_ERASE, 12);
	nsleep(TIME_VppSETUP), progstrobe(TIME_ERASECYCLE), nsleep(TIME_VppHOLD);
	progvoltage(0);
}

void writeinhibit(void)
{
	sendbyte(0x00);
	setchipmode(MD_WRITEINHIBIT, 12);
	nsleep(TIME_VppSETUP), progstrobe(TIME_WRITECYCLE), nsleep(TIME_VppHOLD);
	progvoltage(0);
}

void readinhibit(void)
{
	sendbyte(0x00);
	setchipmode(MD_READINHIBIT, 12);
	nsleep(TIME_VppSETUP), progstrobe(TIME_WRITECYCLE), nsleep(TIME_VppHOLD);
	progvoltage(0);
}

unsigned readid(void)
{
	unsigned id;

	setchipmode(MD_ID, 5);
	id = getbyte();
	incrementaddress();
	id = (id << 8) | getbyte();
	progvoltage(0);

	return id;
}

void readbuffer(unsigned char *buffer, int length)
{
	setchipmode(MD_READ, 5);
	while (length--)
	{
		*buffer++ = getbyte();
		incrementaddress();
	}
	progvoltage(0);
}

int comparebuffer(unsigned char *buffer, int length)
{
	int					address				= 0;

	setchipmode(MD_READ, 5);
	while (length--)
	{
		if (*buffer++ != getbyte())
		{
			progvoltage(0);
			return address;
		}
		incrementaddress();
		address++;
	}
	progvoltage(0);

	return EOF;
}

int blankcheck(int length)
{
	int					address				= 0;

	setchipmode(MD_READ, 5);
	while (length--)
	{
		if (getbyte() != 0xff)
		{
			progvoltage(0);
			return address;
		}
		incrementaddress();
		address++;
	}
	progvoltage(0);

	return EOF;
}

void writebuffer(unsigned char *buffer, int length)
{
	if (length <= 0)
		return;

	setchipmode(MD_WRITE, 12);
	sendbyte(*buffer++);
	nsleep(TIME_VppSETUP);

	while (--length && giveup == 0)
	{
		progstrobe(TIME_WRITECYCLE);
		nsleep(TIME_DATAHOLD);
		sendbyte(*buffer++);
		while (busystatus())
			;
		nsleep(TIME_ADDRHOLD);
		incrementaddress();
	}
	progstrobe(TIME_WRITECYCLE);
	sleepref();
	nspan(TIME_VppHOLD);
	while (busystatus())
		;
	nspan(TIME_VppHOLD + TIME_ADDRHOLD);
	progvoltage(0);
}

void displaybuffer(unsigned char *buffer, int length, int mode)
{
	int					i,
						j;

	if (mode == 0)
	{
		for (i = 0; i < length; i++)
		{
			if ((i & 63) == 0)
				printf("%04x: ", i);

			printf("%c", (buffer[i] & 127) >= 32 && buffer[i] != 127 ? buffer[i] : '.');

			if ((i & 63) == 63)
				printf("\n");
		}

		if ((i & 63) != 0)
			printf("\n");
	}
	else
	{
		for (i = 16; i < length; i += 16)
		{
			printf("%04x: ", i - 16);
			for (j = i - 16; j < i; j++)
				printf("%02x ", buffer[j]);
			printf("| ");
			for (j = i - 16; j < i; j++)
				printf("%c", (buffer[j] & 127) >= 32 && buffer[j] != 127 ? buffer[j] : '.');
			printf("\n");
		}
		printf("%04x: ", i - 16);
		for (j = i - 16; j < length; j++)
			printf("%02x ", buffer[j]);
		while (j++ < i)
			printf("   ");
		printf("| ");
		for (j = i - 16; j < length; j++)
			printf("%c", (buffer[j] & 127) >= 32 && buffer[j] != 127 ? buffer[j] : '.');
		printf("\n");
	}
}

int loadfile(unsigned char *buffer, int length, const char *filename)
{
	FILE			   *fptr;

	if (strcmp(filename, "-") == 0)
		fptr = stdin;
	else if ((fptr = fopen(filename, "rb")) == NULL)
		perror("fopen (r)"), exit(ERR_EXTERNAL);

	if ((length = fread(buffer, 1, length, fptr)) < 0)
		perror("fread"), exit(ERR_EXTERNAL);

	if (fptr != stdin)
	{
		if (fgetc(fptr) != EOF)
			fprintf(stderr, "Extra data ignored.\n");
		fclose(fptr);
	}

	return length;
}

void savefile(unsigned char *buffer, int length, const char *filename)
{
	FILE			   *fptr;

	if (strcmp(filename, "-") == 0)
		fptr = stdout;
	else if ((fptr = fopen(filename, "wb")) == NULL)
		perror("fopen (w)"), exit(ERR_EXTERNAL);

	if (fwrite(buffer, 1, length, fptr) != length)
		perror("fwrite"), exit(ERR_EXTERNAL);

	if (fptr != stdout)
		fclose(fptr);
}

int report(const char *format, ...)
{
	if (beverbose)
	{
		va_list ap;
		va_start(ap, format);

		return vprintf(format, ap);
	}

	return 0;
}

int main(int argc, char *argv[])
{
	static unsigned char buffer[2048] = { 0 };
	int					buflen = 0,
						maxbuflen = sizeof(buffer);
    int                 c,
    					stuff;

	setup_io();

	while ((c = getopt(argc, argv, "ha:tibel:wcrs:dDp:qvV")) != EOF)
		switch (c)
		{
		case 'h':
			printf("proggy [blah blah blah]\n"
					"\t-h\tshow this text\n"
					"\t-a file\tautomatic; equivalent to '-tib[e]l file -wc'\n"
					"\t-t\ttest programmer (returns %d if not found)\n"
					"\t-i\tcheck chip identifier (returns %d if unknown)\n"
					"\t-b\tcheck that ROM is blank (returns %d if not blank)\n"
					"\t-e\terase ROM\n"
					"\t-l file\tload file into buffer\n"
					"\t-w\twrite buffer to ROM\n"
					"\t-c\tcompare ROM with buffer (returns %d if different)\n"
					"\t-r\tread ROM to buffer\n"
					"\t-s file\tsave buffer to file\n"
					"\t-d/-D\tdump buffer to stdout\n"
					"\t-p num\tset protect bits to mode num\n"
					"\t-q\toperate quietly (meaningless)\n"
					"\t-v\topervate verbosely\n"
					"\t-V\tversion information\n",
					ERR_NOPROGRAMMER,
					ERR_BADID,
					ERR_NOTBLANK,
					ERR_COMPAREFAIL);
			break;

		case 'a':
			if (unitpresent() == 0)
				fprintf(stderr, "Programmer not found\n"), exit(ERR_NOPROGRAMMER);
			stuff = readid();
			if (stuff == ID_AT89C1051)
				maxbuflen = 1024;
			else if (stuff == ID_AT89C2051)
				maxbuflen = 2048;
			else
				fprintf(stderr, "Chip identifier %04x unknown\n", stuff), exit(ERR_BADID);
			if (blankcheck(maxbuflen) != EOF)
				chiperase();
			buflen = loadfile(buffer, maxbuflen, optarg);
			writebuffer(buffer, buflen);
			stuff = comparebuffer(buffer, buflen);
			if (stuff != EOF)
				fprintf(stderr, "Verification failed at %04x\n", stuff), exit(ERR_COMPAREFAIL);
			break;

		case 't':
			if (unitpresent() == 0)
				fprintf(stderr, "Programmer not found\n"), exit(ERR_NOPROGRAMMER);

			report("Programmer detected\n");
			break;

		case 'i':
			stuff = readid();
			if (stuff == ID_AT89C1051)
				report("Found AT89C1051\n"), maxbuflen = 1024;
			else if (stuff == ID_AT89C2051)
				report("Found AT89C2051\n"), maxbuflen = 2048;
			else
				fprintf(stderr, "Chip identifier %04x unknown\n", stuff), exit(ERR_BADID);
			break;

		case 'b':
			stuff = blankcheck(maxbuflen);
			if (stuff != EOF)
				printf("Chip contains data at %04x\n", stuff), exit(ERR_NOTBLANK);
			report("Chip appears blank\n");
			break;

		case 'e':
			report("Erasing ROM\n");
			chiperase();
			break;

		case 'l':
			buflen = loadfile(buffer, maxbuflen, optarg);
			report("Loaded %d bytes from %s\n", buflen, optarg);
			break;

		case 'w':
			report("Writing %d bytes to ROM\n", buflen);
			writebuffer(buffer, buflen);
			break;

		case 'c':
			stuff = comparebuffer(buffer, buflen);
			if (stuff != EOF)
				fprintf(stderr, "Verification failed at %04x\n", stuff), exit(ERR_COMPAREFAIL);
			report("verified OK\n");
			break;

		case 'r':
			report("Reading ROM\n");
			readbuffer(buffer, buflen = sizeof(buffer));
			break;

		case 's':
			savefile(buffer, buflen, optarg);
			report("Saved %d bytes to %s\n", buflen, optarg);
			break;

		case 'd':
			displaybuffer(buffer, buflen, 0);
			break;

		case 'D':
			displaybuffer(buffer, buflen, 1);
			break;

		case 'p':
			switch (atoi(optarg))
			{
			case 1:
				report("Protection bits unchanged\n");
				break;

			case 2:
				report("Disabling further writes\n");
				writeinhibit();
				break;

			case 3:
				report("Disabling both read and write\n");
				writeinhibit();
				readinhibit();
				break;

			default:
				fprintf(stderr, "Nonsense argument to -p: %s\n", optarg);
				exit(ERR_USER);
			}
			break;

		case 'q':
			bequiet++;
			break;

		case 'v':
			beverbose++;
			break;

		case 'V':
			printf("I wrote this and I got it right first time.\n");
			break;

		default:
			fprintf(stderr, "Unrecognised argument\n"), exit(ERR_USER);
		}

	if (optind < argc)
		fprintf(stderr, "Extra arguments ignored\n");

	return 0;
}
