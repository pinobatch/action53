// DTE text compressor by JRoatch

#include <stdio.h>   /* I/O */
#include <errno.h>   /* errno */
#include <stdbool.h> /* bool */
#include <stddef.h>  /* null */
#include <stdint.h>  /* uint8_t */
#include <stdlib.h>  /* malloc() */
#include <string.h>  /* memmove() */
#include <getopt.h>  /* getopt_long() */
#include <ctype.h>   /* ispunct() */
#include <limits.h>  /* INT_MIN */

// Added by Pino: Setting stdin/stdout to binary mode under Windows
// All calls to set_fd_binary() also added by Pino
#if defined (_WIN32)
#include <io.h>
#include <fcntl.h>
#define fd_isatty _isatty
#endif
static inline void set_fd_binary(unsigned int fd) {
#ifdef _WIN32
  _setmode(fd, _O_BINARY);
#else
  (void) fd;
#endif
}
// End added by Pino


const char *version_text = "dte 1.2\n";
const char *help_text =
	"dte - Rencode a file to use unused bytes as recursive digram references.\n"
	"\n"
	"Usage:\n"
	"  dte [-d] [options] INPUT [-o] OUTPUT [-t] [TABLE]\n"
	"\n"
	"Options:\n"
	"  -h, --help             show this help message and exit\n"
	"  --version              show program's version number and exit\n"
	"  -o FILE, --output=FILE output to FILE instead of second positional argument\n"
	"  -d, --decode           apply the digram table to the file\n"
	"  -c, --stdout           use standard input/output when filenames are absent\n"
	"  -f, --force            overwrite output file[s] without prompting\n"
	"  -t FILE, --table=FILE  read/write the replacement table from/to FILE\n"
	"                         alternatively can be the third positional argument\n"
	"                         or prepended to the main input/output file by default\n"
	"  -r MIN-MAX, --table-range=MIN-MAX\n"
	"                         The replacement table will be sized to include\n"
	"                         the inclusive range of characters [MIN, MAX]\n"
	"                         (default range: 0-255)\n"
    "  -e N | MIN-MAX, --exclude N | MIN-MAX\n"
	"                         forbid these characters from appearing in digrams\n"
	"                         (multiple exclude ranges can be added)\n"
    "  -m N, --min-freq N     stop when number of times each digram appears\n"
	"                         drops below this amount (default: 3)\n"
	"  -q, --quiet            suppress error messages\n"
	"  -v, --verbose          be more chatty (multiple times is more verbose)\n"
;

static int verbosity_level = 0;
#define debug_message(level, fmt, args...) if (verbosity_level >= level) { fprintf(stderr, fmt, ## args); }

static void fatal_error(const char *msg)
{
	if (verbosity_level >= 0)
		fputs(msg, stderr);
	exit(EXIT_FAILURE);
}

static void fatal_perror(const char *filename)
{
	if (verbosity_level >= 0)
		perror(filename);
	exit(EXIT_FAILURE);
}


/*
"0xa-0x1f" -> [10, 31], "10~31" -> [10, 31], "07 010" -> [7, 8],
"-90" -> [-inf, 90], "90" -> [90, 90], "90-" -> [90, inf]
"" -> no change, "-" -> [-inf, inf], "-90-" -> no change
"-10-20" -> [10, 20]
returns true if no change occurs.
*/
bool get_number_range_from_string(int *begin, int *end, char *input_string) {
	int min;
	int max;
	char *string = input_string;
	char *strtol_ptr;
	char c;
	bool min_tilde_prefixed = false;
	bool max_tilde_prefixed = false;

	while ((c = *string) != '\0') {
		if ((c == '-') || (c == '~'))
			min_tilde_prefixed = true;
		if (isdigit(c))
			break;
		++string;
	}
	min = strtol(string, &strtol_ptr, 0);
	if (strtol_ptr == string) {
		if (min_tilde_prefixed) {
			*begin = INT_MIN;
			*end = INT_MAX;
			return 0;
		}
		return 1;
	}
	string = strtol_ptr;

	while ((c = *string) != '\0') {
		if ((c == '-') || (c == '~')|| (c == ','))
			max_tilde_prefixed = true;
		if (isdigit(c))
			break;
		++string;
	}
	max = strtol(string, &strtol_ptr, 0);
	if (strtol_ptr == string) {
		if (min_tilde_prefixed && max_tilde_prefixed)
			return 1;
		*begin = (min_tilde_prefixed) ? INT_MIN : min;
		*end = (max_tilde_prefixed) ? INT_MAX : min;
		return 0;
	}
	*begin = (min < max) ? min : max;
	*end = (min < max) ? max : min;
	return 0;
}

size_t read_file_to_memory(uint8_t **returned_data_ptr, FILE *in)
{
	uint8_t *data = NULL;
	uint8_t *new_data = NULL;
	size_t capacity;
	size_t previous_fibonacci_number;
	size_t length;
	size_t n;

	/* A read error already occurred? */
	if ((in == NULL) || ferror(in))
		return 0;

	/* if we can query the file size then do it the simple way */
	if (fseek(in, 0, SEEK_END) == 0) {
		capacity = ftell(in);
		if (capacity <= 0)
			return 0;
		rewind(in);
		data = malloc(capacity);
		length = fread(data, 1, capacity, in);
		if (ferror(in)) {
			free(data);
			return 0;
		}
		*returned_data_ptr = data;
		return length;
	}
	/* else proceed with doing realloc a bunch of times */
	rewind(in);

	/* 64 times the 15th fibonacci number is about 32KiB which is
	   the size of the mapped area of a NES cartridge under a 6502 CPU */
	capacity = 39040;
	previous_fibonacci_number = 24128;
	length = 0;

	debug_message(3, "Allocating %lu bytes for reading.\n", (long unsigned)capacity);

	/* first alloc */
	data = malloc(capacity);
	if (data == NULL)
		return 0;

	while (true) {
		n = fread(data + length, 1, capacity - length, in);
		if (ferror(in)) {
			free(data);
			return 0;
		}
		length += n;
		if (n == 0)
			break;

		if (length >= capacity) {
			/* I wanted a slower geometric growth then a simple exponential
			   like "capacity *= 2", so I choose the fibonacci sequence
			   (times 64 due to the size of cache lines) */
			n = capacity;
			capacity = capacity + previous_fibonacci_number;
			previous_fibonacci_number = n;
			debug_message(3, "Reallocating to %lu bytes.\n", (long unsigned)capacity);
			new_data = realloc(data, capacity);
			if (new_data == NULL) {
				free(data);
				return 0;
			}
			data = new_data;
		}
	}
	if (length == 0) {
		free(data);
		return 0;
	}

	/* shrink buffer to fit the final size */
	debug_message(2, "Sizing buffer to input size of %lu bytes.\n", (long unsigned)length);
	new_data = realloc(data, length);
	if (new_data == NULL) {
		free(data);
		return 0;
	}
	data = new_data;

	*returned_data_ptr = data;
	return length;
}

size_t expand_dte(uint8_t **returned_data, uint8_t *input, size_t input_size, uint8_t *digram_table) {
	uint8_t *data = NULL;
	uint8_t *realloc_data = NULL;
	size_t capacity = 0;
	size_t previous_fibonacci_number = 64;
	size_t data_size = 0;
	size_t i, n;
	uint8_t c;
	uint8_t stack[256];
	int stack_size = 0;
	bool char_is_literal[256];

	if (input_size < 2) {
		*returned_data = NULL;
		return 0;
	}

	for (i = 0; i < 256; ++i) {
		char_is_literal[i] = (digram_table[i*2+0] == i) ? true : false;
	}

	while (capacity < (input_size*2)) {
		/* the usual compression ratio of english ascii text is about 50%
		   which is why the "input_size*2" */
		n = capacity;
		capacity = capacity + previous_fibonacci_number;
		previous_fibonacci_number = n;
	}
	debug_message(3, "Allocating %lu bytes for expaning.\n", (long unsigned)capacity);
	data = malloc(capacity);
	if (data == NULL) {
		*returned_data = NULL;
		return 0;
	}

	/* due to a check above, we have ensured at least 1 byte of input */
	i = 0;
	c = input[i];
	++i;
	while (true) {
		if (char_is_literal[c]) {
			data[data_size] = c;
			++data_size;
			if (data_size >= capacity) {
				n = capacity;
				capacity = capacity + previous_fibonacci_number;
				previous_fibonacci_number = n;
				debug_message(3, "Reallocating output buffer to %lu bytes.\n", (long unsigned)capacity);
				realloc_data = realloc(data, capacity);
				if (realloc_data == NULL) {
					free(data);
					*returned_data = NULL;
					return 0;
				}
				data = realloc_data;
			}
			if (stack_size) {
				/* we have stacked characters left to deal with
				   before the geting a character from input */
				--stack_size;
				c = stack[stack_size];
			} else {
				/* get next input character */
				if (i >= input_size)
					break;
				c = input[i];
				++i;
			}
		} else {
			if (stack_size >= 256) {
				/* there's a cycle in the digram table
				   causing the stack to explode here */
				free(data);
				*returned_data = NULL;
				return 0;
			}
			/* place the second character onto a stack to deal with next */
			stack[stack_size] = digram_table[c*2+1];
			++stack_size;
			/* while we go ahead and check to see if this character
			   is a literal or digram at the top of this loop */
			c = digram_table[c*2+0];
		}
	}

	/* shrink buffer to fit the final size */
	debug_message(2, "Sizing output buffer to %lu bytes.\n", (long unsigned)data_size);
	realloc_data = realloc(data, data_size);
	if (realloc_data == NULL) {
		free(data);
		*returned_data = NULL;
		return 0;
	}
	data = realloc_data;

	*returned_data = data;
	return data_size;
}

size_t replace_digram(uint8_t *data, size_t data_length, uint8_t c, uint16_t digram, int digram_counts[65536]) {
	size_t i, j, k;

	uint32_t window;

	debug_message(2, "Replacing %d digrams of [0x%02x,0x%02x] with 0x%02x.\n", digram_counts[digram], (digram>>8)&0xff, digram&0xff, c);

	if (data_length < 2)
		return data_length;

    window = (data[0] << 8*1) | (data[1] << 8*0);
	if (data_length == 2) {
		if ((window & 0xffff) == digram) {
			data[0] = c;
			return 1;
		}
		return 2;
	}

	/* process the first digram */
	k = 0;
	i = 0;
	j = 0;
	window = (window << 8) | (data[i+2]);
	if (((window >> 8) & 0xffff) == digram) {
		/*--digram_counts[digram];*/
		--digram_counts[(window >> 0) & 0xffff];
		window = ((window) & 0x000000ff) | ((window >> 8) & 0x00ff0000) | (c << 8);
		++digram_counts[(window >> 0) & 0xffff];
		j = i+1;
		data[j] = c;
	}
	++i;
	/* process all the middle digrams */
	for (/*i = 1*/; i < data_length-2; ++i) {
		/* window ranges 4 bytes from data[i-1] to data[i+2] */
		window = (window << 8) | (data[i+2]);
		if (((window >> 8) & 0xffff) == digram) {
			debug_message(4, "moving %ld bytes from %ld to %ld.\n", (long unsigned)(i-j), (long unsigned)j, (long unsigned)k);
			memmove(data+k, data+j, i-j);
			k += i-j;
			j = i+1;
			data[j] = c;

			/*--digram_counts[digram];*/
			--digram_counts[(window >> 0) & 0xffff];
			--digram_counts[(window >> 16) & 0xffff];
			window = ((window) & 0x000000ff) | ((window >> 8) & 0x00ff0000) | (c << 8);
			++digram_counts[(window >> 0) & 0xffff];
			++digram_counts[(window >> 8) & 0xffff];
		}
	}
	/* process the last digram */
	window = (window << 8);
	if (((window >> 8) & 0xffff) == digram) {
		debug_message(4, "moving %ld bytes from %ld to %ld.\n", (long unsigned)(i-j), (long unsigned)j, (long unsigned)k);
		memmove(data+k, data+j, i-j);
		k += i-j;
		j = i+1;
		data[k] = c;
		k++;

		/*--digram_counts[digram];*/
		--digram_counts[(window >> 16) & 0xffff];
		window = ((window) & 0x000000ff) | ((window >> 8) & 0x00ff0000) | (c << 8);
		++digram_counts[(window >> 8) & 0xffff];
	} else {
		i += 2;
		/* add 2 to the index due to not replacing the last digram
		   so that the entire last digram is also copied */
		debug_message(4, "moving %ld bytes from %ld to %ld.\n", (long unsigned)(i-j), (long unsigned)j, (long unsigned)k);
		memmove(data+k, data+j, i-j);
		k += i-j;
	}

	digram_counts[digram] = 0;

	return k;
}

enum {
	CHAR_UNUSED         = 0,
	CHAR_USED           = 1 << 0,
	CHAR_FORBIDDEN      = 1 << 1,
};

size_t compress_dte(uint8_t *data, size_t data_size, uint8_t *digram_table, int min_freq) {
	int i, k, n;
	size_t data_index;
	uint8_t l, r;
	uint16_t c, d;
	int digram_count[65536] = {0};
	bool avaliable_char[256];
	bool possible_double_overlap = false;

	/* A character located at it's own location would cause infinite recursion
	   when normally decoded. This is used to instead signal that the entry is
	   *not* occupied by a digram */
	debug_message(4, "Initalizing character digram tables.\n");
	for (i = 0; i < 256; ++i) {
		c = digram_table[i*2+1];
		avaliable_char[i] = (c & (CHAR_USED | CHAR_FORBIDDEN)) ? false : true;
		digram_table[i*2+0] = i;
		digram_table[i*2+1] = 0x00;
		if (c & (CHAR_FORBIDDEN)) {
			/* kill all pairs containing the forbidden character once without
			   having another conditional for every input byte */
			for (k = 0; k < 256; ++k) {
				digram_count[(i*256) + k] = INT_MIN;
				digram_count[(k*256) + i] = INT_MIN;
			}
		}
	}

	if (data_size <= 1)
		return data_size;

	debug_message(4, "Counting digrams.\n");
	for (data_index = 0; data_index < data_size-1; ++data_index) {
		r = data[data_index+0];
		avaliable_char[r] = false;
		l = data[data_index+1];
		/* counting in such a way that 3 of the same character
		   will counted once and not twice, and 4 twice not three times */
		if (!possible_double_overlap) {
			if (r == l)
				possible_double_overlap = true;
			++digram_count[r*256+l];
		} else {
			if (r != l)
				++digram_count[r*256+l];
			possible_double_overlap = false;
		}
		/* TODO: account for the difference between overlapping and
		   non-overlapping digrams in replacement operations */
	}
	r = data[data_index+0];
	avaliable_char[r] = false;

	if (min_freq < 1)
		min_freq = 1;

	for (c = 0; c < 256; ++c) {
		if (!avaliable_char[c])
			continue;
		debug_message(3, "Current data size: %lu.\n", (long unsigned)data_size);
		if (data_size <= 1)
			break;

		/* search for most currently occurring digram */
		d = 0;
		n = 0;
		for (i = 0; i < 65536; ++i) {
			if (digram_count[i] > n) {
				d = i;
				n = digram_count[i];
			}
		}
		/* exit if unable to encode any more digrams due to
		   excluded characters or frequency threshold */
		if (n < min_freq)
			break;

		data_size = replace_digram(data, data_size, c, d, digram_count);
		digram_table[c*2+0] = d >> 8;
		digram_table[c*2+1] = d & 0xff;
	}
	debug_message(4, "Done compressing.\n");

	return data_size;
}

int main (int argc, char *argv[])
{
	char *input_filename = NULL;
	char *output_filename = NULL;
	char *table_filename = NULL;
	FILE *input_file = NULL;
	FILE *output_file = NULL;
	FILE *table_file = NULL;
	int i, n;
	uint8_t *data = NULL;
	size_t data_size;
	uint8_t char_digram_table[512];
	uint8_t *output_data = NULL;
	size_t output_data_size = 0;

	bool decode = false;
	bool overwrite_output_file = false;
	bool overwrite_table_file = false;
	bool use_stdio_for_data = false;
	int table_range_min = 0;
	int table_range_max = 255;
	bool excluded_char[256] = {false};
	int exclude_range_min;
	int exclude_range_max;
	int min_freq = 3;

	int option_index = 0;
	int c;
	while (1) {
		static struct option long_options[] =
		{
			{"help",        no_argument,       NULL, 'h'},
			{"version",     no_argument,       NULL, 'V'},
			{"decode",      no_argument,       NULL, 'd'},
			{"output",      required_argument, NULL, 'o'},
			{"stdout",      no_argument,       NULL, 'c'},
			{"force",       no_argument,       NULL, 'f'},
			{"table",       required_argument, NULL, 't'},
			{"table-range", required_argument, NULL, 'r'},
			{"exclude",     required_argument, NULL, 'e'},
			{"min-freq",    required_argument, NULL, 'm'},
			{"quiet",       no_argument,       NULL, 'q'},
			{"verbose",     no_argument,       NULL, 'v'},
			{NULL, 0, NULL, 0}
		};
		c = getopt_long(argc, argv, "hVdo:t:r:cfe:m:qv", long_options, &option_index);

		if (c == -1)
			break;

		switch (c) {
		case 'h':
			fputs(help_text, stdout);
			return EXIT_SUCCESS;

		break; case 'V':
			fputs(version_text, stdout);
			return EXIT_SUCCESS;

		break; case 'd':
			decode = true;

		break; case 'o':
			output_filename = optarg;

		break; case 'c':
			use_stdio_for_data = true;

		break; case 'f':
			overwrite_output_file = true;
			overwrite_table_file = true;

		break; case 't':
			table_filename = optarg;

		break; case 'r':
			if (get_number_range_from_string(&table_range_min, &table_range_max, optarg))
				fatal_error("Error parsing table range.\n");
			if (table_range_min < 0) table_range_min = 0;
			if (table_range_min > 255) table_range_min = 255;
			if (table_range_max < 0) table_range_max = 0;
			if (table_range_max > 255) table_range_max = 255;

		break; case 'e':
			if (get_number_range_from_string(&exclude_range_min, &exclude_range_max, optarg))
				fatal_error("Error parsing exclude range.\n");
			if (exclude_range_min < 0) exclude_range_min = 0;
			if (exclude_range_min > 255) exclude_range_min = 255;
			if (exclude_range_max < 0) exclude_range_max = 0;
			if (exclude_range_max > 255) exclude_range_max = 255;
			for (i = exclude_range_min; i <= exclude_range_max; ++i) {
				excluded_char[i] = true;
			}

		break; case 'm':
			min_freq = strtol(optarg, NULL, 0);

		break; case 'q':
			verbosity_level = -1;
			opterr = 0;

		break; case 'v':
			if (verbosity_level >= 0)
				++verbosity_level;

		break; case '?':
			/* getopt_long already printed an error message. */
			exit(EXIT_FAILURE);

		break; default:
		break;
		}
	}

	if (verbosity_level < 0) {
		fclose(stderr);
	}

	if (min_freq <= 0)
		fatal_error("--min-freq must be greater than 0.\n");

	debug_message(4, "Opening files.\n");
	if ((input_filename == NULL) && (optind < argc)) {
		input_filename = argv[optind];
		++optind;
	}
	if ((output_filename == NULL) && (optind < argc)) {
		output_filename = argv[optind];
		++optind;
	}
	if ((table_filename == NULL) && (optind < argc)) {
		table_filename = argv[optind];
		++optind;
	}
	if ((!use_stdio_for_data) && (input_filename == NULL) && (output_filename == NULL)) {
		fatal_error("Input and output filenames required. Try --help for more info.\n");
	}
	if (input_filename == NULL) {
		if (use_stdio_for_data) {
			input_file = stdin;
			set_fd_binary(0);
			input_filename = "<stdin>";
		} else {
			fatal_error("input filename required. Try --help for more info.\n");
		}
	}
	if (output_filename == NULL) {
		if (use_stdio_for_data) {
			output_file = stdout;
			set_fd_binary(1);
			output_filename = "<stdout>";
		} else {
			fatal_error("output filename required. Try --help for more info.\n");
		}
	}
	/* ask to overwrite output file */
	if ((output_file == NULL) && (!overwrite_output_file)) {
		/* open output for read to check for file existence. */
		output_file = fopen(output_filename, "rb");
		if (errno == ENOENT) {
			/* File not found, so we good to put one there */
			overwrite_output_file = true;
			errno = 0;
			if (output_file != NULL)
				fclose(output_file);
			output_file = NULL;
		} else {
			if (output_file != NULL)
				fclose(output_file);
			output_file = NULL;
			if (verbosity_level >= 0) {
				fputs(output_filename, stderr);
				fputs(" already exists;", stderr);
				if (!use_stdio_for_data) {
					fputs(" do you wish to overwrite (y/N) ? ", stderr);
					c = fgetc(stdin);
					if (c != '\n') {
						while (true) {
							if (fgetc(stdin) == '\n')
								break; /* read until the newline */
						}
					}
					if (c == 'y' || c == 'Y') {
						overwrite_output_file = true;
					} else {
						fputs("    not overwritten.\n", stderr);
					}
				} else {
					fputs(" not overwritten.\n", stderr);
				}
			}
		}
		/* if user said no (or quiet flag blocked the question) then exit. */
		if (!overwrite_output_file)
			exit(EXIT_FAILURE);
	}

	/* ask to overwrite output table file, if the option was provided */
	if ((!decode) && (table_filename != NULL) && (!overwrite_table_file)) {
		/* open file for read to check for file existence. */
		table_file = fopen(table_filename, "rb");
		if (errno == ENOENT) {
			/* File not found, so we good to put one there */
			overwrite_table_file = true;
			errno = 0;
			if (table_file != NULL)
				fclose(table_file);
			table_file = NULL;
		} else {
			if (table_file != NULL)
				fclose(table_file);
			table_file = NULL;
			if (verbosity_level >= 0) {
				fputs(table_filename, stderr);
				fputs(" already exists;", stderr);
				if (!use_stdio_for_data) {
					fputs(" do you wish to overwrite (y/N) ? ", stderr);
					c = fgetc(stdin);
					if (c != '\n') {
						while (true) {
							if (fgetc(stdin) == '\n')
								break; /* read until the newline */
						}
					}
					if (c == 'y' || c == 'Y') {
						overwrite_table_file = true;
					} else {
						fputs("    not overwritten\n", stderr);
					}
				} else {
					fputs(" not overwritten\n", stderr);
				}
			}
		}
		/* if user said no (or quiet flag blocked the question) then exit. */
		if (!overwrite_table_file)
			exit(EXIT_FAILURE);
	}

	/* open output if we don't already have it set to stdin */
	if (!input_file) {
		fclose(stdin);
		input_file = fopen(input_filename, "rb");
		if (input_file == NULL) {
			fatal_perror(input_filename);
		}
		setvbuf(input_file, NULL, _IONBF, 0);
	}

	/* open input, again if not already stdout */
	if ((!output_file) && (overwrite_output_file)) {
		fclose(stdout);
		output_file = fopen(output_filename, "wb");
		if (output_file == NULL) {
			fatal_perror(output_filename);
		}
		setvbuf(output_file, NULL, _IONBF, 0);
	}

	/* open table file if option is specified and we passed the question above */
	if (table_filename != NULL) {
		if (decode) {
			table_file = fopen(table_filename, "rb");
			if (table_file == NULL) {
				fatal_perror(table_filename);
			}
			setvbuf(input_file, NULL, _IONBF, 0);
		} else if (overwrite_table_file) {
			table_file = fopen(table_filename, "wb");
			if (table_file == NULL) {
				fatal_perror(table_filename);
			}
			setvbuf(table_file, NULL, _IONBF, 0);
		}
	} else {
		table_filename = "<prepended>";
	}

	debug_message(1, "Reading input file \"%s\".\n", input_filename);
	data_size = read_file_to_memory(&data, input_file);
	fclose(input_file);

	/* init table to all literals */
	for (i = 0; i < 256; ++i) {
		char_digram_table[i*2+0] = i;
		char_digram_table[i*2+1] = 0x00;
	}

	if (decode) {
		debug_message(1, "reading digrams from \"%s\".\n", table_filename);
		if (table_file) {
			i = ((table_range_max+1) - table_range_min)*2;
			n = fread(char_digram_table+(table_range_min*2), 1, i, table_file);
			if (n < i) {
				fatal_error("Failed to read the full range of the digram table.\n");
			}
			output_data_size = expand_dte(&output_data, data, data_size, char_digram_table);
		} else {
			i = ((table_range_max+1) - table_range_min)*2;
			memcpy(char_digram_table+(table_range_min*2), data+0, i);
			output_data_size = expand_dte(&output_data, data+i, data_size-i, char_digram_table);
		}
		debug_message(1, "Writing data (%lu bytes) to \"%s\".\n", (long unsigned)data_size, output_filename);
		if (output_data_size > 0) {
			fwrite(output_data, sizeof(uint8_t), output_data_size, output_file);
			free(output_data);
			output_data = NULL;
		}
	} else {
		debug_message(4, "placing option flags for character digrams.\n");
		for (i = 0; i < 256; ++i) {
			c = ((table_range_min <= i) && (i <= table_range_max)) ? CHAR_UNUSED : CHAR_USED;
			if (excluded_char[i])
				c |= CHAR_FORBIDDEN;
			char_digram_table[i*2+1] = c;
		}

		data_size = compress_dte(data, data_size, char_digram_table, min_freq);

		/* TODO: check for write errors */
		i = ((table_range_max+1) - table_range_min)*2;
		debug_message(1, "Writing replacement table (%lu bytes) to \"%s\".\n", (long unsigned)i, table_filename);
		if (table_file) {
			fwrite(char_digram_table+(table_range_min*2), sizeof(uint8_t), i, table_file);
		} else {
			fwrite(char_digram_table+(table_range_min*2), sizeof(uint8_t), i, output_file);
		}
		debug_message(1, "Writing data (%lu bytes) to \"%s\".\n", (long unsigned)data_size, output_filename);
		fwrite(data, sizeof(uint8_t), data_size, output_file);
	}

	fclose(output_file);
	if (table_file)
		fclose(table_file);

	free(data);
	data = NULL;
	return EXIT_SUCCESS;
}
