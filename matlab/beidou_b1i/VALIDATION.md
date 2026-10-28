# Validation record — v4 (2026-10-27)

## v4 actually executed here

- MISS_HIT static MATLAB parser/linter: all 37 .m files parse without reported errors.
- Independent NumPy/SciPy TX reference, not MATLAB execution: PRN source with fractional cell-integrated edges, normalized Rapp/AMPM, designed response FIR, fixed power calibration, anti-alias and windowed-sinc resampling.
- A/B deterministic internal sampling convergence: 8x versus 32x relative RMS 0.12651% / 0.12399%; 16x versus 32x 0.02567% / 0.02516%. This is one 4ms fixture, not every scenario.
- AA maximum response from output Nyquist to 12MHz: -75.30dB. Phase-noise theoretical AR-mixture mask fit maximum error 0.5271dB, RMS phase 0.007137rad (not a 10Hz PLL tracking measurement).
- Realized A extra response: 0.04680dB peak-to-peak and 0.9347ns peak-to-peak in the stated band; targets 0.05dB/1ns are not silently reported as realized values.
- Independent hardware fixtures include PN, weak spur, Doppler, receiver noise/FIR. A/B target PRN12 peak about 13.455, ratio 7.151, threshold 2.208; wrong PRN13 and noise do not pass. This tests model mathematics, NOT the delivered MATLAB generator and not a false-alarm certification.
- FFT streaming FIR matches direct filtering to maximum error 5.7e-16, including chunks shorter than filter memory.
- Fractional 1ns edge movement changes the area-integrated source.
- See verification/tx_reference_results.json and check_tx_reference.py.

## v4 tests supplied but NOT executed here

No MATLAB/Octave is installed. The following still require MATLAB R2024a:

- test_bds_tx_hardware(false): JSON roundtrip/rejection, exact saved-IQ invariance under receive-block and segment changes, A/B differences with identical RX noise, master bypass equality, blind saved-file target/control checks, random-stream query splitting, optional edge/IQ excitation.
- test_bds_tx_hardware(true): also renders and saves the six model diagnostic panels.
- bds_tx_convergence: MATLAB counterpart to deterministic 8x/16x/32x reference check.
- test_bds_simulator(false): original signal/storage/acquisition tests plus TX tests.
- 5s/60s complete MATLAB generation and hardware graphics have NOT been run here.

TX model scopes, assumptions, PSD extensions, power/time references and commands are documented in TX_HARDWARE_zh.md. No RF fingerprint classifier or real-device validation is supplied.

---

## Historical v2/v3 validation records (scope unchanged)

# Validation record — v2

Date: 2026-10-25.

## Actually executed

- MISS_HIT MATLAB static parser/linter: all19 `.m` files parsed without reported errors, including the handle-class writer.
- Independent Python storage invariants: six combinations of recording length, segment size and compute-block size; exact ordered reconstruction, fixed non-final sizes, short final file without padding, continuous global sample indices, full-file byte equality and one-byte corruption differentiation.
- Independent whole-file analysis reference: all10003 complex-tone samples included; PSD peak at +64 Hz; integrated PSD approximately0.49 W, including a final partial FFT window. See `verification/storage_reference_results.json`.
- Original independent BCH/PRN/noise reference results retained unchanged in `verification/reference_results.json`; the signal core did not change in v2.

These are mathematical/reference and static checks, NOT execution of the delivered MATLAB implementation.

## MATLAB tests provided, not executed in this environment

Run `test_bds_simulator` in MATLAB R2024a. It includes:

- Original BCH exhaustive codebook, PRN known vector, all D1 pages, week crossover and geometry checks.
- Short generated signal with different compute-block and segment boundaries; identical sample readback; operation with no full file; actual final partial segment count; unique output directories.
- `test_bds_storage`: deterministic writer fixture, segment-to-full byte comparisons, cross-boundary reading, sample/power/extrema coverage, complex PSD frequency sign and normalization; intentional corruption and file-size damage must be rejected.
- Graphics: one-segment full I/Q/PSD figure; whole-run PNG/FIG/MAT saved in the run directory. Graphics tests use invisible windows. `test_bds_simulator(false)` skips graphics checks.

No MATLAB or Octave runtime is available here. Full60-second generation, MATLAB graphics rendering, and the MATLAB tests above have not been executed locally. The user supplied v1 MATLAB plots earlier, but those do not validate v2.

## Scope limits

No independent GNSS receiver decode/timing test, real-RF or real-device validation, hardware-fingerprint model, or STFT matrix was added.

## v3 addition — 2026-10-25

Actually executed:

- Static MATLAB parser/linter: all24 `.m` files, including five new acquisition-related files, parsed without reported errors.
- Independent Python acquisition reference with three distinct PRN/delay/Doppler fixtures at prefilter C/N0=45 dB-Hz, sampled8.184 MHz, filtered noise and NH/data sign changes.
- All three target hypotheses detected; other-PRN and paired noise controls did not pass. Delay error <=2 samples, Doppler error <=500 Hz. First fixture: normalized peak14.117 vs nominal threshold2.208, peak ratio7.462.
- Ten additional independent noise diagnostics: 0 detections, maximum normalized peak approximately2.019. This finite result does NOT certify Pfa=1e-3 or imply zero false alarms.
- Correlation score invariance under input amplitude scaling checked.

Actual numbers: `verification/acquisition_reference_results.json`.

Not executed here:

- `test_bds_acquisition` (MATLAB), which adds known-parameter recovery, zero/noise inputs, saved segmented-file searches, deliberately unusable truth/timing metadata, controls and evidence-graphics saving.
- Acquisition on the user's actual saved waveforms and MATLAB rendering of the new figure.

The Python reference checks validate the numerical design but do not execute the `.m` implementation. Existing v1/v2 records above retain their original scope. No navigation decoding or hardware fingerprint model was added.
