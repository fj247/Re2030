# v4 — 2026-10-27

- 默认开启等效TX硬件链路，A/B完整配置、总开关和各模块开关。
- 均匀发射时间轴上处理DAC、滤波、Rapp/AMPM、PN和杂散，再映射接收时间；独立随机流、连续分块。
- 可选IQ、下降沿非对称、相关数字码时序抖动；不自动生成设备标签。
- JSON保存加载、实际设计/功率标定、有效模块状态、手动诊断和收敛夹具。
- 总开关关闭直接旁路到v3理想路径；输出格式、分段及原PRN验证接口兼容。
- 内部响应FIR随采样率缩放物理时长；PN采用拟合AR混合而非巨长高率FIR，实际误差透明保存。
- 本环境没有MATLAB/Octave；验证范围见VALIDATION.md和独立参考结果。

# v3 — 2026-10-25

- Added manual `bds_validate_signal`: blind PRN code-delay/Doppler search from saved I/Q.
- Added split-half PCPS/noncoherent accumulation for NH/data-transition robustness.
- Added nominal Gamma/median-background threshold plus competing-peak-ratio screening; actual Pfa explicitly uncertified.
- Added multiple probe windows, non-target PRN and independently filtered/scaled noise-only controls.
- Added correlation search/slice/control/repeat plots and MAT/JSON evidence reports in a new analysis subdirectory.
- Existing waveform, segmentation and automatic overview behavior unchanged; no NAV decode or fingerprinting added.
- Added MATLAB acquisition self-tests and executed independent Python reference diagnostics; MATLAB execution remains untested here.

# v2 — 2026-10-25

- Default1-second segments and optional full continuous file (enabled).
- Unique directory for every run; fixed-width sequence names; JSON/CSV zero-based sample index.
- Split only at the file writer; no per-file signal processing, state reset or tail padding.
- Automatic structural and, when enabled, full-to-segments byte comparison.
- Manual whole-segment I/Q envelope and mean complex PSD; optional local pointwise view.
- Automatic whole-run overview PNG, FIG and numeric summaries in the run directory.
- Streaming reads/analysis; no full-record memory allocation or STFT matrix.
- v1 JSON remains readable; v2 samples can be read from segments without a full file.
- Extended MATLAB self-tests and explicit validation status. No MATLAB runtime was available during this update.

Use `result.metadataFile` instead of assuming the JSON lives directly in `bds_output`.
Call `bds_quicklook(result.metadataFile,3)` for segment3.
