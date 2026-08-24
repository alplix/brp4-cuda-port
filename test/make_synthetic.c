/***************************************************************************
 * Synthetic BRP4 input generator for local end-to-end testing of the
 * custom Windows CUDA build (no BOINC work unit required).
 *
 * Produces:
 *   synthetic.binary : uncompressed dedispersed time series (DD_Header +
 *                      signed 8-bit samples, read transparently via gzread).
 *                      Contains a pure sinusoid at --freq (default 100 Hz)
 *                      plus weak noise, quantized with the header's scale.
 *   bank.txt         : three binary templates ("P_b tau Psi0" per line)
 *   zaplist.txt      : empty RFI list
 *
 * Usage: make_synthetic [--samples N] [--freq HZ] [--scale S]
 *                        [--templates N] [--outdir DIR]
 *
 * The sample values are chosen so that the injected spectral line lands well
 * inside the searched frequency range (bin = freq * Tobs < f0 * Tobs).
 ***************************************************************************/

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "../src/structs.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

int main(int argc, char **argv) {
  unsigned int n_samples = 131072; /* 2^17 */
  double freq_hz = 100.0;
  double scale = 64.0;
  double tsample_us = 64.0; /* micro seconds */
  const char *outdir = ".";
  unsigned int n_templates = 3;

  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--samples") && i + 1 < argc) {
      n_samples = (unsigned int)strtoul(argv[++i], NULL, 10);
    }
    else if (!strcmp(argv[i], "--templates") && i + 1 < argc) {
      n_templates = (unsigned int)strtoul(argv[++i], NULL, 10);
    }
    else if (!strcmp(argv[i], "--freq") && i + 1 < argc) {
      freq_hz = atof(argv[++i]);
    }
    else if (!strcmp(argv[i], "--scale") && i + 1 < argc) {
      scale = atof(argv[++i]);
    }
    else if (!strcmp(argv[i], "--outdir") && i + 1 < argc) {
      outdir = argv[++i];
    }
    else {
      fprintf(stderr, "unknown/ incomplete option: %s\n", argv[i]);
      return 1;
    }
  }

  double tobs_s = (double)n_samples * tsample_us * MICROSEC;

  /* ---- time series file -------------------------------------------- */

  DD_Header head;
  memset(&head, 0, sizeof(head));
  head.tsample = tsample_us;
  head.tobs = tobs_s;
  head.timestamp = 60000.0;    /* arbitrary MJD */
  head.fcenter = 1380.0;       /* MHz */
  head.fchan = 3.0;
  head.RA = 900000.0;          /* hhmmss.s -> 9h 0m 0s */
  head.DEC = 450000.0;         /* ddmmss.s -> +45d 0m 0s */
  head.gal_l = 55.0;
  head.gal_b = -2.0;
  head.DM = 48.2;              /* pc cm^-3, mirrors the J1907 test set */
  head.scale = scale;
  head.filesize = 0;
  head.datasize = n_samples;   /* one byte per sample in .binary format */
  head.nsamples = n_samples;
  head.smprec = (uint16_t)(n_samples > 65535 ? 65535 : n_samples);
  head.nchan = 1;
  head.nifs = 1;
  head.lagformat = 0;
  head.sum = 0;
  head.level = 0;
  strncpy(head.name, "SYNTHETIC", sizeof(head.name) - 1);
  strncpy(head.originalfile, "synthetic.filterbank", sizeof(head.originalfile) - 1);
  strncpy(head.proj_id, "local_test", sizeof(head.proj_id) - 1);
  strncpy(head.observers, "nobody", sizeof(head.observers) - 1);

  char path[1024];
  snprintf(path, sizeof(path), "%s/synthetic.binary", outdir);
  FILE *out = fopen(path, "wb");
  if (out == NULL) {
    perror(path);
    return 1;
  }
  if (fwrite(&head, sizeof(head), 1, out) != 1) {
    perror("fwrite header");
    return 1;
  }

  srand(42); /* deterministic pseudo-noise */
  double dt = tsample_us * MICROSEC;
  for (unsigned int n = 0; n < n_samples; n++) {
    double signal = sin(2.0 * M_PI * freq_hz * (double)n * dt);
    double noise = ((double)rand() / (double)RAND_MAX) - 0.5; /* +-0.5 */
    double value = 20.0 * signal + noise;
    long q = lround(value * scale);
    if (q > 127) q = 127;
    if (q < -127) q = -127;
    signed char sample = (signed char)q;
    if (fwrite(&sample, 1, 1, out) != 1) {
      perror("fwrite sample");
      return 1;
    }
  }
  fclose(out);
  printf("wrote %s (%u samples, %.3f s @ %.0f us, line at %g Hz -> bin %.1f)\n",
         path, n_samples, tobs_s, tsample_us, freq_hz, freq_hz * tobs_s);

  /* ---- template bank ------------------------------------------------ */

  snprintf(path, sizeof(path), "%s/bank.txt", outdir);
  out = fopen(path, "w");
  if (out == NULL) {
    perror(path);
    return 1;
  }
  if (n_templates == 3) {
    fprintf(out, "7200 0.50 0.25\n");
    fprintf(out, "3600 1.00 0.50\n");
    fprintf(out, "1440 2.00 0.75\n");
  }
  else {
    /* deterministic spread of P_b over [360 .. 7200] s so that the injected
     * line (P = 1/freq) is always covered by some template */
    for (unsigned int t = 0; t < n_templates; t++) {
      double frac = (n_templates > 1) ? (double)t / (double)(n_templates - 1) : 0.0;
      double p_b = 7200.0 - frac * (7200.0 - 360.0);
      double tau = 0.25 + 0.75 * ((t % 4) / 3.0);   /* 0.25 .. 1.00 */
      double psi0 = 0.125 + 0.625 * ((t % 8) / 7.0); /* 0.125 .. 0.75 */
      fprintf(out, "%.3f %.3f %.3f\n", p_b, tau, psi0);
    }
  }
  fclose(out);
  printf("wrote %s (%u templates)\n", path, n_templates);

  /* ---- zaplist ------------------------------------------------------- */

  snprintf(path, sizeof(path), "%s/zaplist.txt", outdir);
  out = fopen(path, "w");
  if (out == NULL) {
    perror(path);
    return 1;
  }
  fclose(out);
  printf("wrote %s (empty)\n", path);

  return 0;
}
