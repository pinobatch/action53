#include <stdio.h>   /* I/O */
#include <errno.h>   /* errno */
#include <stdlib.h>  /* exit(), strtol() */
#include <stdbool.h> /* bool */
#include <stddef.h>  /* null */
#include <stdint.h>  /* uint8_t */
#include <string.h>  /* memcpy() */
#include <getopt.h>  /* getopt_long() */

const char *VERSION_TEXT = "Donut 1.7\n";
const char *HELP_TEXT =
	"Donut NES CHR Codec\n"
	"\n"
	"Usage:\n"
	"  donut [-d] [options] INPUT [-o] OUTPUT\n"
	"  donut -h | --help\n"
	"  donut --version\n"
	"\n"
	"Options:\n"
	"  -h --help              show this help message and exit\n"
	"  --version              show program's version number and exit\n"
	"  -z, --compress         compress input file [default action]\n"
	"  -d, --decompress       decompress input file\n"
	"  -o FILE, --output=FILE\n"
	"                         output to FILE instead of second positional argument\n"
	"  -c --stdout            use standard input/output when filenames are absent\n"
	"  -f, --force            overwrite output without prompting\n"
	"  -q, --quiet            suppress error messages\n"
	"  -v, --verbose          show completion stats\n"
	"  --no-bit-flip          don't encode bit rotated blocks\n"
	"  --cycle-limit INT      limits the 6502 decoding time for each encoded block,\n"
	"                         must be at least 1268\n"
;

static int verbosity_level = 0;
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

/* According to a strace of cat on my system, and a quick dd of dev/zero:
   131072 is the optimal block size,
   but that's 2 times the size of the entire 6502 address space!
   The usual data input is going to be 512 tiles of NES gfx data. */
#define BUF_IO_SIZE 8192
#define BUF_GAP_SIZE 512
#define BUF_TOTAL_SIZE ((BUF_IO_SIZE+BUF_GAP_SIZE)*2)

static uint8_t byte_buffer[BUF_TOTAL_SIZE];

#define OUTPUT_BEGIN (byte_buffer)
#define INPUT_BEGIN (byte_buffer + BUF_TOTAL_SIZE - BUF_IO_SIZE)

int popcount8(uint8_t x)
{
	/* would be nice if I could get this to compile to 1 CPU instruction. */
	x = (x & 0x55 ) + ((x >>  1) & 0x55 );
	x = (x & 0x33 ) + ((x >>  2) & 0x33 );
	x = (x & 0x0f ) + ((x >>  4) & 0x0f );
	return (int)x;
}

typedef struct buffer_pointers {
	uint8_t *dest_begin; /* first valid byte */
	uint8_t *dest_end;   /* one past the last valid byte */
	                     /* length is infered as end - begin. */
	uint8_t *src_begin;
	uint8_t *src_end;
} buffer_pointers;

enum {
	DESTINATION_FULL,
	SOURCE_EMPTY,
	SOURCE_IS_PARTIAL,
	ENCOUNTERED_UNDEFINED_BLOCK
};

uint64_t flip_plane_bits_135(uint64_t plane)
{
	uint64_t result = 0;
	uint64_t t;
	int i;
	if (plane == 0xffffffffffffffff)
		return plane;
	if (plane == 0x0000000000000000)
		return plane;
	for (i = 0; i < 8; ++i) {
		t = plane >> i;
		t &= 0x0101010101010101;
		t *= 0x0102040810204080;
		t >>= 56;
		t &= 0xff;
		result |= t << (i*8);
	}
	return result;
}

int pack_pb8(uint8_t *buffer_ptr, uint64_t plane, uint8_t top_value)
{
	uint8_t pb8_ctrl;
	uint8_t pb8_byte;
	uint8_t c;
	uint8_t *p;
	int i;
	p = buffer_ptr;
	++p;
	pb8_ctrl = 0;
	pb8_byte = top_value;
	for (i = 0; i < 8; ++i) {
		c = plane >> (8*(7-i));
		if (c != pb8_byte) {
			*p = c;
			++p;
			pb8_byte = c;
			pb8_ctrl |= 0x80>>i;
		}
	}
	*buffer_ptr = pb8_ctrl;
	return p - buffer_ptr;
}

uint64_t read_plane(uint8_t *p)
{
	return (
		((uint64_t)*(p+0) << (8*0)) |
		((uint64_t)*(p+1) << (8*1)) |
		((uint64_t)*(p+2) << (8*2)) |
		((uint64_t)*(p+3) << (8*3)) |
		((uint64_t)*(p+4) << (8*4)) |
		((uint64_t)*(p+5) << (8*5)) |
		((uint64_t)*(p+6) << (8*6)) |
		((uint64_t)*(p+7) << (8*7))
	);
}

void write_plane(uint8_t *p, uint64_t plane)
{
	*(p+0) = (plane >> (8*0)) & 0xff;
	*(p+1) = (plane >> (8*1)) & 0xff;
	*(p+2) = (plane >> (8*2)) & 0xff;
	*(p+3) = (plane >> (8*3)) & 0xff;
	*(p+4) = (plane >> (8*4)) & 0xff;
	*(p+5) = (plane >> (8*5)) & 0xff;
	*(p+6) = (plane >> (8*6)) & 0xff;
	*(p+7) = (plane >> (8*7)) & 0xff;
}

int cblock_cost(uint8_t *p, int l)
{
	int cycles;
	uint8_t block_header;
	uint8_t plane_def;
	int pb8_count;
	bool decode_only_1_pb8_plane;
	uint8_t short_defs[4] = {0x00, 0x55, 0xaa, 0xff};
	if (l < 1)
		return 0;
	block_header = *p;
	--l;
	if (block_header >= 0xc0)
		return 0;
	if (block_header == 0x2a)
		return 1268;
	cycles = 1298;
	if (block_header & 0xc0)
		cycles += 640;
	if (block_header & 0x20)
		cycles += 4;
	if (block_header & 0x10)
		cycles += 4;
	if (block_header & 0x02) {
		if (l < 1)
			return 0;
		plane_def = *(p+1);
		--l;
		cycles += 5;
		decode_only_1_pb8_plane = ((block_header & 0x04) && (plane_def != 0x00));
	} else {
		plane_def = short_defs[(block_header & 0x0c) >> 2];
		decode_only_1_pb8_plane = false;
	}
	pb8_count = popcount8(plane_def);
	cycles += (block_header & 0x01) ? (pb8_count * 614) : (pb8_count * 75);
	if (!decode_only_1_pb8_plane) {
		l -= pb8_count;
		cycles += l * 6;
	} else {
		--l;
		cycles += 1 * pb8_count;
		cycles += (l * 6 * pb8_count);
	}
	return cycles;
}

bool all_pb8_planes_match(uint8_t *p, int pb8_length, int number_of_pb8_planes)
{
	int i, c, l;
	if (number_of_pb8_planes <= 1) {
		return false;
		/* a block of 0 dupplicate pb8 planes is 1 byte more then normal,
		   and a normal block of 1 plane is 5 cycles less to decode */
	}
	l = number_of_pb8_planes*pb8_length;
	for (c = 0, i = pb8_length; i < l; ++i, ++c) {
		if (c >= pb8_length) {
			c = 0;
		}
		if (*(p + c) != *(p + i)) {
			return false;
		}
	}
	return true;
}

int decompress_blocks(buffer_pointers *result_p, bool allow_partial)
{
	buffer_pointers p;
	uint64_t plane;
	uint64_t prev_plane = 0;
	int i, j, l;
	uint8_t block_header;
	uint8_t plane_def;
	uint8_t pb8_flags;
	uint8_t pb8_byte;
	uint8_t short_defs[4] = {0x00, 0x55, 0xaa, 0xff};
	bool less_then_74_bytes_left;
	bool decode_only_1_pb8_plane;
	uint8_t *single_pb8_plane_ptr;
	p = *(result_p);
	while (p.src_begin - p.dest_end >= 64) {
		less_then_74_bytes_left = (p.src_end - p.src_begin < 74);
		if (less_then_74_bytes_left && (p.src_end - p.src_begin < 1)) {
			return SOURCE_EMPTY;
		}
		block_header = *(p.src_begin);
		++(p.src_begin);
		if (block_header >= 0xc0) {
			return ENCOUNTERED_UNDEFINED_BLOCK;
		}
		if (block_header == 0x2a) {
			l = p.src_end - p.src_begin;
			if (less_then_74_bytes_left && (l < 64)) {
				if (!allow_partial)
					return SOURCE_IS_PARTIAL;
				memset(p.dest_end, 0x00, 64);
			} else {
				l = 64;
			}
			memmove(p.dest_end, p.src_begin, l);
			p.src_begin += l;
			p.dest_end += 64;
		} else {
			single_pb8_plane_ptr = NULL;
			if (block_header & 0x02) {
				if (less_then_74_bytes_left && (p.src_end - p.src_begin < 1)) {
					if (!allow_partial)
						return SOURCE_IS_PARTIAL;
					plane_def = 0x00;
				} else {
					plane_def = *(p.src_begin);
					++(p.src_begin);
				}
				decode_only_1_pb8_plane = ((block_header & 0x04) && (plane_def != 0x00));
				single_pb8_plane_ptr = p.src_begin;
			} else {
				plane_def = short_defs[(block_header & 0x0c) >> 2];
				decode_only_1_pb8_plane = false;
			}
			for (i = 0; i < 8; ++i) {
				if ((((i & 1) == 0) && (block_header & 0x20)) || ((i & 1) && (block_header & 0x10))) {
					plane = 0xffffffffffffffff;
				} else {
					plane = 0x0000000000000000;
				}
				if (plane_def & 0x80) {
					if (decode_only_1_pb8_plane) {
						p.src_begin = single_pb8_plane_ptr;
					}
					if (less_then_74_bytes_left && (p.src_end - p.src_begin < 1)) {
						if (!allow_partial)
							return SOURCE_IS_PARTIAL;
						pb8_flags = 0x00;
						plane_def = 0x00;
					} else {
						pb8_flags = *(p.src_begin);
						++p.src_begin;
					}
					pb8_byte = (uint8_t)plane;
					for (j = 0; j < 8; ++j) {
						if (pb8_flags & 0x80) {
							if (less_then_74_bytes_left && (p.src_end - p.src_begin < 1)) {
								if (!allow_partial)
									return SOURCE_IS_PARTIAL;
								pb8_flags = 0x00;
								plane_def = 0x00;
							} else {
								pb8_byte = *(p.src_begin);
								++p.src_begin;
							}
						}
						pb8_flags <<= 1;
						plane <<= 8;
						plane |= pb8_byte;
					}
					if (block_header & 0x01) {
						plane = flip_plane_bits_135(plane);
					}
				}
				plane_def <<= 1;
				if (i & 1) {
					if (block_header & 0x80) {
						prev_plane ^= plane;
					}
					if (block_header & 0x40) {
						plane ^= prev_plane;
					}
					write_plane(p.dest_end, prev_plane);
					p.dest_end += 8;
					write_plane(p.dest_end, plane);
					p.dest_end += 8;
				} else {
					prev_plane = plane;
				}
			}
		}
		*(result_p) = p;
	}
	return DESTINATION_FULL;
}

int compress_blocks(buffer_pointers *result_p, bool allow_partial, bool use_bit_flip, int cycle_limit)
{
	buffer_pointers p;
	uint64_t block[8];
	uint64_t plane;
	uint64_t plane_predict;
	int shortest_length;
	int least_cost;
	int a, i, r, l;
	uint8_t temp_cblock[74];
	uint8_t *temp_p;
	uint8_t plane_def;
	uint8_t short_defs[4] = {0x00, 0x55, 0xaa, 0xff};
	bool planes_match;
	uint64_t first_non_zero_plane;
	uint64_t first_non_zero_plane_predict;
	int number_of_pb8_planes;
	int first_pb8_length;
	p = *(result_p);
	while (p.src_begin - p.dest_end >= 65) {
		l = p.src_end - p.src_begin;
		if (l <= 0) {
			return SOURCE_EMPTY;
		} else if (l < 64) {
			if (!allow_partial)
				return SOURCE_IS_PARTIAL;
			memset(p.dest_end + 1, 0x00, 64);
		} else {
			l = 64;
		}
		*(p.dest_end) = 0x2a;
		memmove(p.dest_end + 1, p.src_begin, l);
		p.src_begin += l;
		shortest_length = 65;
		least_cost = 1268;
		for (i = 0; i < 8; ++i) {
			block[i] = read_plane((p.dest_end + 1) + (i*8));
		}
		for (r = 0; r < 2; ++r) {
			if (r == 1) {
				if (use_bit_flip) {
					for (i = 0; i < 8; ++i) {
						block[i] = flip_plane_bits_135(block[i]);
					}
				} else {
					break;
				}
			}
			for (a = 0; a < 0xc; ++a) {
				temp_p = temp_cblock + 2;
				plane_def = 0x00;
				number_of_pb8_planes = 0;
				planes_match = true;
				first_pb8_length = 0;
				first_non_zero_plane = 0;
				first_non_zero_plane_predict = 0;
				for (i = 0; i < 8; ++i) {
					plane = block[i];
					if (i & 1) {
						plane_predict = (a & 0x1) ? 0xffffffffffffffff : 0x0000000000000000;
						if (a & 0x4) {
							plane ^= block[i-1];
						}
					} else {
						plane_predict = (a & 0x2) ? 0xffffffffffffffff : 0x0000000000000000;
						if (a & 0x8) {
							plane ^= block[i+1];
						}
					}
					plane_def <<= 1;
					if (plane != plane_predict) {
						l = pack_pb8(temp_p, plane, (uint8_t)plane_predict);
						temp_p += l;
						plane_def |= 1;
						if (number_of_pb8_planes == 0) {
							first_non_zero_plane_predict = plane_predict;
							first_non_zero_plane = plane;
							first_pb8_length = l;
						} else if (first_non_zero_plane != plane) {
							planes_match = false;
						} else if (first_non_zero_plane_predict != plane_predict) {
							planes_match = false;
						}
						++number_of_pb8_planes;
					}
				}
				if (number_of_pb8_planes <= 1) {
					planes_match = false;
					/* a normal block of 1 plane is cheaper to decode,
					   and may even be smaller. */
				}
				temp_cblock[0] = r | (a<<4) | 0x02;
				temp_cblock[1] = plane_def;
				l = temp_p - temp_cblock;
				temp_p = temp_cblock;
				if (all_pb8_planes_match(temp_p+2, first_pb8_length, number_of_pb8_planes)) {
					*(temp_p + 0) = r | (a<<4) | 0x06;
					l = 2 + first_pb8_length;
				} else if (planes_match) {
					*(temp_p + 0) = r | (a<<4) | 0x06;
					l = 2 + pack_pb8(temp_p+2, first_non_zero_plane, ~(uint8_t)first_non_zero_plane);
				} else {
					for (i = 0; i < 4; ++i) {
						if (plane_def == short_defs[i]) {
							++temp_p;
							*(temp_p + 0) = r | (a<<4) | (i << 2);
							--l;
							break;
						}
					}
				}
				if (l <= shortest_length) {
					i = cblock_cost(temp_p, l);
					if ((i <= cycle_limit) && ((l < shortest_length) || (i < least_cost))) {
						memmove(p.dest_end, temp_p, l);
						shortest_length = l;
						least_cost = i;
					}
				}
			}
		}
		p.dest_end += shortest_length;
		*(result_p) = p;
	}
	return DESTINATION_FULL;
}

uint64_t fill_dont_care_bits(uint64_t plane, uint64_t dont_care_mask, uint64_t xor_bg, uint8_t top_value) {
	uint64_t result_plane = 0;
	uint64_t backwards_smudge_plane = 0;
	uint64_t current_byte, mask, inv_mask;
	int i;
	if (dont_care_mask == 0x0000000000000000)
		return plane;

	current_byte = top_value;
	for (i = 0; i < 8; ++i) {
		mask = dont_care_mask & ((uint64_t)0xff << (i*8));
		inv_mask = ~dont_care_mask & ((uint64_t)0xff << (i*8));
		current_byte = (current_byte & mask) | (plane & inv_mask);
		backwards_smudge_plane |= current_byte;
		current_byte = current_byte << 8;
	}
	backwards_smudge_plane ^= xor_bg & dont_care_mask;

	current_byte = (uint64_t)top_value << 56;
	for (i = 0; i < 8; ++i) {
		mask = dont_care_mask & ((uint64_t)0xff << (8*(7-i)));
		inv_mask = ~dont_care_mask & ((uint64_t)0xff << (8*(7-i)));
		if ((plane & inv_mask) == (current_byte & inv_mask)) {
			current_byte = (current_byte & mask) | (plane & inv_mask);
		} else {
			current_byte = (backwards_smudge_plane & mask) | (plane & inv_mask);
		}
		result_plane |= current_byte;
		current_byte = current_byte >> 8;
	}

	return result_plane;
}

/*  most of this copied pasted from compress_blocks,
    but with fill_dont_care_bits sprinkled throughout */
int compress_blocks_with_dcb(buffer_pointers *result_p, bool allow_partial, bool use_bit_flip, int cycle_limit)
{
	buffer_pointers p;
	uint64_t original_block[8];
	uint64_t block[8];
	uint64_t mask[8];
	uint64_t plane;
	uint64_t plane_predict;
	uint64_t plane_predict_l;
	uint64_t plane_predict_m;
	int shortest_length;
	int least_cost;
	int a, i, r, l;
	uint8_t temp_cblock[74];
	uint8_t *temp_p;
	uint8_t plane_def;
	uint8_t short_defs[4] = {0x00, 0x55, 0xaa, 0xff};
	bool planes_match;
	uint64_t first_non_zero_plane;
	uint64_t first_non_zero_plane_predict;
	int number_of_pb8_planes;
	int first_pb8_length;
	p = *(result_p);
	while (p.src_begin - p.dest_end >= 65) {
		l = p.src_end - p.src_begin;
		if (l <= 0) {
			return SOURCE_EMPTY;
		} else if (l < 128) {
			if (!allow_partial)
				return SOURCE_IS_PARTIAL;
			memset(p.dest_end + 1, 0x00, 64);
		} else {
			l = 64;
		}
		*(p.dest_end) = 0x2a;
		memmove(p.dest_end + 1, p.src_begin, l);
		p.src_begin += l;
		shortest_length = 65;
		least_cost = 1268;
		for (i = 0; i < 8; ++i) {
			original_block[i] = read_plane((p.dest_end + 1) + (i*8));
		}
		if (p.src_end - p.src_begin > 0){
			for (i = 0; i < 8; ++i) {
				mask[i] = read_plane((p.src_begin) + (i*8));
			}
			p.src_begin += 64;
		} else {
			for (i = 0; i < 8; ++i) {
				mask[i] = 0;
			}
		}
		for (r = 0; r < 2; ++r) {
			if (r == 1) {
				if (use_bit_flip) {
					for (i = 0; i < 8; ++i) {
						original_block[i] = flip_plane_bits_135(original_block[i]);
					}
					for (i = 0; i < 8; ++i) {
						mask[i] = flip_plane_bits_135(mask[i]);
					}
				} else {
					break;
				}
			}
			for (a = 0; a < 0xc; ++a) {
				for (i = 0; i < 8; i += 2) {
					plane_predict_l = (a & 0x2) ? 0xffffffffffffffff : 0x0000000000000000;
					block[i+0] = fill_dont_care_bits(original_block[i+0], mask[i+0], 0, plane_predict_l);
					plane_predict_m = (a & 0x1) ? 0xffffffffffffffff : 0x0000000000000000;
					block[i+1] = fill_dont_care_bits(original_block[i+1], mask[i+1], 0, plane_predict_m);

					if (a & 0x8)
						block[i+0] = fill_dont_care_bits(block[i+0], mask[i+0], block[i+1], plane_predict_l);
					if (a & 0x4)
						block[i+1] = fill_dont_care_bits(block[i+1], mask[i+1], block[i+0], plane_predict_m);
				}
				temp_p = temp_cblock + 2;
				plane_def = 0x00;
				number_of_pb8_planes = 0;
				planes_match = true;
				first_pb8_length = 0;
				first_non_zero_plane = 0;
				first_non_zero_plane_predict = 0;
				for (i = 0; i < 8; ++i) {
					plane = block[i];
					if (i & 1) {
						plane_predict = (a & 0x1) ? 0xffffffffffffffff : 0x0000000000000000;
						if (a & 0x4) {
							plane ^= block[i-1];
						}
					} else {
						plane_predict = (a & 0x2) ? 0xffffffffffffffff : 0x0000000000000000;
						if (a & 0x8) {
							plane ^= block[i+1];
						}
					}
					plane_def <<= 1;
					if (plane != plane_predict) {
						l = pack_pb8(temp_p, plane, (uint8_t)plane_predict);
						temp_p += l;
						plane_def |= 1;
						if (number_of_pb8_planes == 0) {
							first_non_zero_plane_predict = plane_predict;
							first_non_zero_plane = plane;
							first_pb8_length = l;
						} else if (first_non_zero_plane != plane) {
							planes_match = false;
						} else if (first_non_zero_plane_predict != plane_predict) {
							planes_match = false;
						}
						++number_of_pb8_planes;
					}
				}
				if (number_of_pb8_planes <= 1) {
					planes_match = false;
					/* a normal block of 1 plane is cheaper to decode,
					   and may even be smaller. */
				}
				temp_cblock[0] = r | (a<<4) | 0x02;
				temp_cblock[1] = plane_def;
				l = temp_p - temp_cblock;
				temp_p = temp_cblock;
				if (all_pb8_planes_match(temp_p+2, first_pb8_length, number_of_pb8_planes)) {
					*(temp_p + 0) = r | (a<<4) | 0x06;
					l = 2 + first_pb8_length;
				} else if (planes_match) {
					*(temp_p + 0) = r | (a<<4) | 0x06;
					l = 2 + pack_pb8(temp_p+2, first_non_zero_plane, ~(uint8_t)first_non_zero_plane);
				} else {
					for (i = 0; i < 4; ++i) {
						if (plane_def == short_defs[i]) {
							++temp_p;
							*(temp_p + 0) = r | (a<<4) | (i << 2);
							--l;
							break;
						}
					}
				}
				if (l <= shortest_length) {
					i = cblock_cost(temp_p, l);
					if ((i <= cycle_limit) && ((l < shortest_length) || (i < least_cost))) {
						memmove(p.dest_end, temp_p, l);
						shortest_length = l;
						least_cost = i;
					}
				}
			}
		}
		p.dest_end += shortest_length;
		*(result_p) = p;
	}
	return DESTINATION_FULL;
}

int main (int argc, char **argv)
{
	int c;
	char *input_filename = NULL;
	char *output_filename = NULL;
	FILE *input_file = NULL;
	FILE *output_file = NULL;
	bool decompress = false;
	bool force_overwrite = false;
	bool use_stdio_for_data = false;
	bool no_bit_flip_blocks = false;
	bool interleaved_dont_care_bits = false;

	int total_bytes_in = 0;
	int total_bytes_out = 0;
	float total_bytes_ratio = 0.0;

	buffer_pointers p = {NULL};
	size_t l;

	int cycle_limit = 10000;

	int status;

	setvbuf(stdin, NULL, _IONBF, 0);
	setvbuf(stdout, NULL, _IONBF, 0);
	setvbuf(stderr, NULL, _IONBF, 0);
	while (1) {
		static struct option long_options[] =
		{
			{"help",        no_argument,       NULL, 'h'},
			{"version",     no_argument,       NULL, 'V'},
			{"compress",    no_argument,       NULL, 'z'},
			{"decompress",  no_argument,       NULL, 'd'},
			{"output",      required_argument, NULL, 'o'},
			{"stdout",      no_argument,       NULL, 'c'},
			{"force",       no_argument,       NULL, 'f'},
			{"verbose",     no_argument,       NULL, 'v'}, /* to be used */
			{"quiet",       no_argument,       NULL, 'q'},
			{"no-bit-flip", no_argument,       NULL, 'b'+256},
			{"cycle-limit", required_argument, NULL, 'y'+256},
			{"interleaved-dont-care-bits", no_argument, NULL, 'd'+256},
			{NULL, 0, NULL, 0}
		};
		/* getopt_long stores the option index here. */
		int option_index = 0;

		c = getopt_long(argc, argv, "hVzdo:cfvq",
						long_options, &option_index);

		/* Detect the end of the options. */
		if (c == -1)
			break;

		switch (c) {
		case 'h':
			fputs(HELP_TEXT, stdout);
			exit(EXIT_SUCCESS);

		break; case 'V':
			fputs(VERSION_TEXT, stdout);
			exit(EXIT_SUCCESS);

		break; case 'z':
			decompress = false;

		break; case 'd':
			decompress = true;

		break; case 'o':
			output_filename = optarg;

		break; case 'c':
			use_stdio_for_data = true;

		break; case 'f':
			force_overwrite = true;

		break; case 'v':
			if (verbosity_level >= 0)
				++verbosity_level;

		break; case 'q':
			verbosity_level = -1;
			opterr = 0;

		break; case 'b'+256:
			no_bit_flip_blocks = true;

		break; case 'y'+256:
			cycle_limit = strtol(optarg, NULL, 0);

		break; case 'd'+256:
			interleaved_dont_care_bits = true;

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

	if (cycle_limit < 1268) {
		fatal_error("Invalid parameter for --cycle-limit. Must be a integer >= 1268.\n");
	}

	if ((input_filename == NULL) && (optind < argc)) {
		input_filename = argv[optind];
		++optind;
	}

	if ((output_filename == NULL) && (optind < argc)) {
		output_filename = argv[optind];
		++optind;
	}

	if ((input_filename == NULL) && (output_filename == NULL) && (!use_stdio_for_data)) {
		fatal_error("Input and output filenames required. Try --help for more info.\n");
	}

	if (input_filename == NULL) {
		if (use_stdio_for_data) {
			input_file = stdin;
		} else {
			fatal_error("input filename required. Try --help for more info.\n");
		}
	}

	if (output_filename == NULL) {
		if (use_stdio_for_data) {
			output_file = stdout;
		} else {
			fatal_error("output filename required. Try --help for more info.\n");
		}
	}

	if (output_filename != NULL) {
		fclose(stdout);
		if (!force_overwrite) {
			/* open output for read to check for file existence. */
			output_file = fopen(output_filename, "rb");
			if (output_file != NULL) {
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
							force_overwrite = true;
						} else {
							fputs("    not overwritten\n", stderr);
						}
					} else {
						fputs(" not overwritten\n", stderr);
					}
				}
			}
		}
		if ((errno == ENOENT) || (force_overwrite)) {
			/* "No such file or directory" means the name is usable */
			errno = 0;
			output_file = fopen(output_filename, "wb");
			if (output_file == NULL) {
				fatal_perror(output_filename);
			}
			setvbuf(output_file, NULL, _IONBF, 0);
		} else {
			/* error message printed above */
			exit(EXIT_FAILURE);
		}
	} else {
		output_filename = "<stdout>";
	}

	if (input_filename != NULL) {
		fclose(stdin);
		input_file = fopen(input_filename, "rb");
		if (input_file == NULL) {
			fatal_perror(input_filename);
		}
		setvbuf(input_file, NULL, _IONBF, 0);
	} else {
		input_filename = "<stdin>";
	}

	p.src_begin = INPUT_BEGIN;
	p.src_end = INPUT_BEGIN;
	p.dest_begin = OUTPUT_BEGIN;
	p.dest_end = OUTPUT_BEGIN;
	status = SOURCE_EMPTY;
	while(true) {
		l = (size_t)(p.src_end - p.src_begin);
		if ((l <= BUF_GAP_SIZE) && !feof(input_file)) {
			if (l > 0) {
				memmove(INPUT_BEGIN - l, p.src_begin, l);
			}
			p.src_begin = INPUT_BEGIN - l;
			p.src_end = INPUT_BEGIN;

			l = fread(INPUT_BEGIN, sizeof(uint8_t), (size_t)BUF_IO_SIZE, input_file);
			if (ferror(input_file)) {
				fatal_perror(input_filename);
			}
			p.src_end += l;
			total_bytes_in += l;
		}

		if (decompress) {
			status = decompress_blocks(&p, feof(input_file));
		} else if (interleaved_dont_care_bits) {
			status = compress_blocks_with_dcb(&p, feof(input_file), !no_bit_flip_blocks, cycle_limit);
		} else {
			status = compress_blocks(&p, feof(input_file), !no_bit_flip_blocks, cycle_limit);
		}

		l = (size_t)(p.dest_end - p.dest_begin);
		if (l >= BUF_IO_SIZE) {
			l = fwrite(p.dest_begin, sizeof(uint8_t), (size_t)BUF_IO_SIZE, output_file);
			if (ferror(output_file)) {
				fatal_perror(output_filename);
			}
			p.dest_begin += l;
			total_bytes_out += l;

			l = (size_t)(p.dest_end - p.dest_begin);
			if (l > 0) {
				memmove(OUTPUT_BEGIN, p.dest_begin, l);
			}
			p.dest_begin = OUTPUT_BEGIN;
			p.dest_end = OUTPUT_BEGIN + l;
		}

		if ((feof(input_file) && (status == SOURCE_EMPTY)) || (status == ENCOUNTERED_UNDEFINED_BLOCK)) {
			l = (size_t)(p.dest_end - p.dest_begin);
			if (l > 0) {
				l = fwrite(p.dest_begin, sizeof(uint8_t), (size_t)l, output_file);
				if (ferror(output_file)) {
					fatal_error(output_filename);
				}
				p.dest_begin += l;
				total_bytes_out += l;
			}
			if (status == ENCOUNTERED_UNDEFINED_BLOCK) {
				fatal_error("Error: Unhandled block header >= 0xc0.\n");
			}
			break;
		}
	}

	if (input_file != NULL) {
		fclose(input_file);
	}

	if (output_file != NULL) {
		fclose(output_file);
	}

	if (verbosity_level >= 1) {
		/* I was hoping I would avoid printf for this, because printf is stupid */
		if (decompress) {
			if (total_bytes_out != 0) {
				total_bytes_ratio = (1.0 - ((float)total_bytes_in / (float)total_bytes_out))*100.0;
			}
		} else {
			if (total_bytes_in != 0) {
				total_bytes_ratio = (1.0 - ((float)total_bytes_out / (float)total_bytes_in))*100.0;
			}
		}
		fprintf (stderr, "%s :%#5.1f%% (%d => %d bytes)\n", output_filename, total_bytes_ratio, total_bytes_in, total_bytes_out);
	}

	exit(EXIT_SUCCESS);
}
