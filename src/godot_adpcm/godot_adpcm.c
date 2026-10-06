// IMA ADPCM encoder producing exactly the layout Godot 4.3's AudioStreamWAV expects
// (port of ResourceImporterWAV::_compress_ima_adpcm): per channel a 4 byte zero header,
// then 4-bit nibbles, low nibble first; stereo channels are encoded separately and the
// two byte streams interleaved L,R,L,R.
//
// usage: godot_adpcm <in.pcm16le> <out.adpcm> <channels 1|2> [<in_rate> <max_rate> <mono_db>]
//          With rates: resample to max_rate when in_rate is higher (windowed sinc low-pass), and
//          fold stereo to mono when the side signal is at least mono_db below the mid signal
//          (0 disables). Prints "rate=<hz> channels=<n> frames=<n>" for the caller.
//        godot_adpcm --verify <in.pcm16le> <in.adpcm> <channels>   (decodes like Godot, prints SNR)
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const int16_t step_table[89] = {
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
	50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
	337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
	2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
	15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767};
static const int8_t index_table[16] = {-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8};

static int clampi(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

// Encode n samples taken every `stride` from in; returns bytes written (n_even/2 + 4).
static size_t encode(const int16_t *in, size_t n, size_t stride, uint8_t *out) {
	size_t len = n + (n & 1);
	int step_idx = 0, prev = 0;
	uint8_t *o = out;
	*o++ = 0; *o++ = 0; *o++ = 0; *o++ = 0;
	for (size_t i = 0; i < len; i++) {
		int sample = i < n ? in[i * stride] : 0;
		int diff = sample - prev, step = step_table[step_idx], vpdiff = step >> 3;
		uint8_t nibble = 0;
		if (diff < 0) { nibble = 8; diff = -diff; }
		for (int mask = 4; mask; mask >>= 1, step >>= 1)
			if (diff >= step) { nibble |= mask; diff -= step; vpdiff += step; }
		prev = clampi(nibble & 8 ? prev - vpdiff : prev + vpdiff, -32768, 32767);
		step_idx = clampi(step_idx + index_table[nibble], 0, 88);
		if (i & 1) *o++ |= nibble << 4; else *o = nibble;
	}
	return len / 2 + 4;
}

static void *slurp(const char *path, size_t *size) {
	FILE *f = fopen(path, "rb");
	if (!f) { perror(path); exit(1); }
	fseek(f, 0, SEEK_END); *size = ftell(f); fseek(f, 0, SEEK_SET);
	void *buf = malloc(*size ? *size : 1);
	if (fread(buf, 1, *size, f) != *size) { perror(path); exit(1); }
	fclose(f);
	return buf;
}

static int verify(const char *pcm_path, const char *adpcm_path, int ch) {
	size_t ps, as;
	int16_t *pcm = slurp(pcm_path, &ps);
	uint8_t *ad = slurp(adpcm_path, &as);
	size_t frames = ps / 2 / ch;
	double sig = 0, err = 0;
	for (int c = 0; c < ch; c++) {
		int pred = 0, idx = 0;
		// Godot's decoder starts at byte 0, so the 4 header bytes decode as 8 leading nibbles.
		for (size_t k = 0; k < frames + 8; k++) {
			uint8_t b = ad[(k >> 1) * ch + c];
			int nib = (k & 1) ? b >> 4 : b & 0xF, step = step_table[idx];
			idx = clampi(idx + index_table[nib], 0, 88);
			int diff = step >> 3;
			if (nib & 1) diff += step >> 2;
			if (nib & 2) diff += step >> 1;
			if (nib & 4) diff += step;
			if (nib & 8) diff = -diff;
			pred = clampi(pred + diff, -32768, 32767);
			if (k >= 8) {
				double s = pcm[(k - 8) * ch + c], e = s - pred;
				sig += s * s; err += e * e;
			}
		}
	}
	printf("frames=%zu channels=%d ratio=%.2fx SNR=%.1f dB\n", frames, ch, (double)ps / as,
	       err > 0 ? 10 * log10(sig / err) : 999.0);
	return 0;
}

// Fold near-identical stereo to mono. Returns the new channel count.
static int maybe_mono(int16_t *pcm, size_t frames, double mono_db) {
	double mid = 0, side = 0;
	for (size_t i = 0; i < frames; i++) {
		double l = pcm[i * 2], r = pcm[i * 2 + 1];
		mid += (l + r) * (l + r); side += (l - r) * (l - r);
	}
	if (mono_db <= 0 || (mid > 0 && 10 * log10((side + 1e-9) / mid) > -mono_db)) return 2;
	for (size_t i = 0; i < frames; i++) pcm[i] = (int16_t)((pcm[i * 2] + pcm[i * 2 + 1]) / 2);
	return 1;
}

// Band-limited resample (Hann-windowed sinc, cutoff just under the new Nyquist frequency).
static long gcdl(long a, long b) { while (b) { long t = a % b; a = b; b = t; } return a; }

// Hann windowed sinc low pass resampler from in_rate to out_rate (out_rate < in_rate). Output
// frame j sits at input position j * in_rate / out_rate; its fractional part takes only
// out_rate / gcd(in_rate, out_rate) distinct values, so the kernel is computed once per phase.
static int16_t *resample(const int16_t *in, size_t frames, int ch, long in_rate, long out_rate, size_t *out_frames) {
	double ratio = (double)out_rate / in_rate;
	size_t n = (size_t)floor(frames * ratio);
	if (n < 1) n = 1;
	int16_t *out = malloc(n * ch * sizeof(int16_t));
	double fc = 0.5 * ratio * 0.92;  // cycles per input sample
	int taps = (int)ceil(6.0 / ratio), width = 2 * taps;
	long g = gcdl(in_rate, out_rate), phases = out_rate / g;
	double *kern = calloc((size_t)phases * width, sizeof(double));
	char *ready = calloc((size_t)phases, 1);
	for (size_t j = 0; j < n; j++) {
		long long pos = (long long)j * in_rate;
		long center = (long)(pos / out_rate), ph = (long)(pos % out_rate) / g;
		double *h = kern + (size_t)ph * width;
		if (!ready[ph]) {
			double frac = (double)(ph * g) / out_rate, wsum = 0;
			for (int i = 0; i < width; i++) {
				double x = frac + taps - 1 - i, w = 0.5 + 0.5 * cos(M_PI * x / taps);  // x = t - k
				h[i] = (fabs(x) < 1e-9 ? 2 * fc : sin(2 * M_PI * fc * x) / (M_PI * x)) * w;
				wsum += h[i];
			}
			for (int i = 0; i < width; i++) h[i] /= wsum;
			ready[ph] = 1;
		}
		for (int c = 0; c < ch; c++) {
			double acc = 0;
			for (int i = 0; i < width; i++) {
				long k = center - taps + 1 + i;
				if (k >= 0 && k < (long)frames) acc += in[k * ch + c] * h[i];
			}
			out[j * ch + c] = (int16_t)clampi((int)lround(acc), -32768, 32767);
		}
	}
	free(kern); free(ready);
	*out_frames = n;
	return out;
}

int main(int argc, char **argv) {
	if (argc == 5 && !strcmp(argv[1], "--verify")) return verify(argv[2], argv[3], atoi(argv[4]));
	if (argc != 4 && argc != 7) { fprintf(stderr, "usage: %s <in.pcm16le> <out.adpcm> <channels 1|2> [<in_rate> <max_rate> <mono_db>]\n", argv[0]); return 2; }
	int ch = atoi(argv[3]);
	if (ch != 1 && ch != 2) { fprintf(stderr, "channels must be 1 or 2\n"); return 2; }
	size_t size;
	int16_t *pcm = slurp(argv[1], &size);
	size_t frames = size / 2 / ch;
	int rate = argc == 7 ? atoi(argv[4]) : 0;
	if (argc == 7) {
		int max_rate = atoi(argv[5]);
		if (ch == 2) ch = maybe_mono(pcm, frames, atof(argv[6]));
		if (max_rate > 0 && rate > max_rate) {
			size_t nf;
			int16_t *rs = resample(pcm, frames, ch, rate, max_rate, &nf);
			free(pcm); pcm = rs; frames = nf; rate = max_rate;
		}
	}
	size_t per = (frames + (frames & 1)) / 2 + 4;
	uint8_t *out = malloc(per * ch), *tmp = malloc(per);
	if (ch == 1) {
		encode(pcm, frames, 1, out);
	} else {
		for (int c = 0; c < 2; c++) {
			encode(pcm + c, frames, 2, tmp);
			for (size_t i = 0; i < per; i++) out[i * 2 + c] = tmp[i];
		}
	}
	FILE *f = fopen(argv[2], "wb");
	if (!f || fwrite(out, 1, per * ch, f) != per * ch) { perror(argv[2]); return 1; }
	fclose(f);
	if (argc == 7) printf("rate=%d channels=%d frames=%zu\n", rate, ch, frames);
	return 0;
}
