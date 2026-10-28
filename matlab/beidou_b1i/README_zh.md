# 北斗 B1I／D1 单卫星正常波形仿真 v4

MATLAB R2024a，使用基础MATLAB，无需专用工具箱。只生成正常合成接收信号，没有射频发射、攻击或监测识别功能。保留v2的连续分段、完整文件、全段I/Q频谱和自动概览。v3新增手动PRN相关捕获与对照验证；v4默认加入可配置的等效发射机射频非理想模型。详细配置、A/B切换、总开关和来源见 **TX_HARDWARE_zh.md**。

## 1. 先运行小数据

解压到新目录，避免新旧同名函数混在 MATLAB 路径中。切换当前文件夹到本代码目录：

```matlab
clear classes
addpath(pwd)
test_bds_simulator
```

默认自检包含隐藏窗口的绘图/保存测试。只测信号、文件与数值分析，不测试图形环境：

```matlab
test_bds_simulator(false)
```

打开 `run_bds_simulation.m`，第一次建议把总时长改为5秒：

```matlab
cfg.durationSeconds=5;
cfg.segmentSeconds=1;
cfg.keepFullFile=true;
cfg.autoOverview=true;
```

然后执行：

```matlab
run_bds_simulation
```

运行完成后，变量 `result` 包含本次运行目录和元数据路径。**每次运行创建独立目录**，不会接续或覆盖上一次运行；这没有改变旧版“重复配置重现同一场景”的行为。

## 1.1 从I/Q验证信号存在性（新增，手动调用）

```matlab
evidence=bds_validate_signal(result.metadataFile);
```

可直接分析旧版已保存的数据，不需要重新生成。提供相关搜索图、峰值切片、其他PRN/纯噪声对照和多个时间片的参数对比，保存独立证据报告。只验证PRN匹配结构，不验证导航电文帧或设备指纹。门限为近似统计参考，不声称精确虚警率。

完整说明见 `SIGNAL_PRESENCE_zh.md`，新增自检为 `test_bds_acquisition`。

## 2. 默认参数及文件大小

| 设置 | 默认值 | 含义 |
|---|---|---|
| `durationSeconds` | 60 | 一次连续运行总时长，可改5、10等 |
| `segmentSeconds` | 1 | 每段保存长度；末段按实际长度保存 |
| `keepFullFile` | true | 同时保留完整波形 |
| `verifyFullFile` | true | 生成后重新读取文件，逐字节验证完整文件与分段拼接一致 |
| `autoOverview` | true | 每次运行后自动生成、保存全程概览 |
| `overviewVisible` | true | 同时显示概览窗口；设false仅保存 |
| `plotMaxBins` | 2000 | 时域显示最多约2000个统计区间，不改变原始数据 |
| `analysisFftLength` | 4096 | 分块平均频谱的FFT长度 |
| `blockSamples` | 163680 | 内部计算块，独立于文件分段和电文帧 |

波形为小端 float32 I/Q交织，每个复采样8字节，采样率8.184 MHz。每秒约65.472 MB。

| 总时长 | 默认分段数 | 仅分段数据量 | 同时保留完整文件总量 |
|---|---:|---:|---:|
| 5秒 | 5 | 约327 MB | 约655 MB |
| 10秒 | 10 | 约655 MB | 约1.31 GB |
| 60秒 | 60 | 约3.93 GB | 约7.86 GB |
| 5分钟 | 300 | 约19.64 GB | 约39.28 GB |

这些值不含少量参数/图形文件。分段不减少总数据量。默认逐字节验证和全程概览均需额外读盘，但不会把所有数据载入内存。运行时间取决于本机CPU、磁盘和总采样数。

## 3. 每次运行目录

`bds_output` 下每轮创建类似 `b1i_single_normal_20261025_143012_123` 的目录。同毫秒重名时附加递增后缀。

| 文件 | 内容 |
|---|---|
| `b1i_single_normal.iq.f32` | 完整连续波形；`keepFullFile=false`时不创建 |
| `segment_000001.iq.f32` 等 | 按顺序编号的分段，无附加处理、不补零 |
| `b1i_single_normal.json` | 总参数、分段索引、功率、验证和概览状态 |
| `tx_hardware_profile.json` / `tx_hardware_design.json` | 实际硬件配置及模型系数/标定/随机过程拟合 |
| `segment_index.csv` | 可读的序号、文件名、全局起始采样编号、实际采样数、时间、字节数 |
| `b1i_single_normal_truth.mat` | 配置、电文真值和低速传播真值，不是从波形解调所得 |
| `overview.png` | 自动生成的全程概览图 |
| `overview.fig` | 可在MATLAB中重新打开的概览图 |
| `overview_stats.mat` | 概览曲线和平均频谱的统计值 |

例如12.3秒、每段1秒，将产生12个1秒文件和1个0.3秒文件。索引的 `startSample` 从0计数，区间为 `[startSample, startSample+sampleCount)`。

I/Q文件没有头部，排列为 `I0,Q0,I1,Q1,...`，单位为 `sqrt(W)`，约定复包络平均功率为 `E[|I+jQ|^2]`。完整文件与分段共用一次float32转换后的同一批采样。跨文件不重置载波、码、电文、滤波器或随机序列。

运行未完成时目录中保留 `INCOMPLETE.txt`，未闭合的文件保留 `.partial`。不要把这样的目录作为完成的数据集。正常波形写入和验证结束后移除该标记。

## 4. 单分段图：手动执行，不自动弹出

查看第1个分段，使用该段全部采样：

```matlab
bds_quicklook(result.metadataFile,1)
```

查看第3个分段：

```matlab
bds_quicklook(result.metadataFile,3)
```

图中包含I时域、Q时域、复数I+jQ的平均功率谱密度。长区间时域用每个显示区间的最小值—最大值绘制，频谱采用全段分块平均；不是只看开头20毫秒。

局部查看：第2段内0.1秒开始的100微秒：

```matlab
bds_quicklook(result.metadataFile,2,0.1,0.0001)
```

短至每个显示区间只有一个采样时，直接绘制逐点波形。显示幅度使用 `n sqrt(W)`（即10^-9 sqrt(W)），避免截图时遗漏科学计数倍率；**文件中仍保存原始sqrt(W)单位**。

图形统计不会写回或改变小文件；不额外归一化、不对原始波形再滤波。每次调用仅打开一个三联图。默认不自动保存单段图，需要时可用MATLAB窗口或 `savefig` 自行保存。

`bds_quicklook` 也兼容旧版v1单文件JSON：省略序号或传1，默认分析整个旧文件。

## 5. 全程概览：每次运行自动执行和保存

包括五个面板：

1. 整次运行I分量的分时段幅度范围。
2. 整次运行Q分量的分时段幅度范围。
3. 分时段平均接收总功率曲线，**包含信号和噪声**。
4. 使用整次运行所有采样得到的平均复基带频谱。
5. 开头、中间、结尾的代表性短区间频谱叠加，每个最多0.2秒；短记录自动去重。

概览保存在本轮目录中，与完整文件同级。不计算、不保存STFT二维时频矩阵。全程时域/功率图中每个统计区间都参加统计，没有抽掉中间的大段数据。

手动重新生成：

```matlab
bds_overview(result.metadataFile)
```

仅保存、不显示：

```matlab
bds_overview(result.metadataFile,false)
```

重新打开已保存图形：

```matlab
openfig(fullfile(result.runDirectory,'overview.fig'))
```

若MATLAB图形环境或图片保存失败，波形不会被删除：程序发出明确警告，JSON中 `overviewStatus` 为 `failed`，目录中保存 `overview_error.txt`。解决图形环境问题后可手动重画。

## 6. 读取数据与检查一致性

从整次运行第1秒开始读取20毫秒，允许跨分段：

```matlab
[iq,meta]=bds_read_iq(result.metadataFile,1,0.02);
```

从第3段开头读取20毫秒：

```matlab
[iq,meta]=bds_read_iq(result.metadataFile,0,0.02,3);
```

精确按全局采样编号读取：

```matlab
iq=bds_read_samples(result.metadataFile,10000,8192);
```

v2读取函数优先使用索引中的分段文件，完整大文件不是读取所必需的。修改分段或删除分段会改变/破坏相应读取结果；请把原始数据保留好。

重新执行完整验证：

```matlab
report=bds_verify_files(result.metadataFile,true)
```

检查索引、样本数和字节数，且在保留完整文件时逐字节检查拼接一致。设为false仅跳过逐字节比较，仍验证结构和文件大小；不保留完整文件时只做结构验证。

## 7. 分段与指纹数据

存储分段长度不等于模型输入窗口长度。后续可以从这些文件中再读取毫秒级窗口，跨边界时按全局采样编号读取即可。末段不补零，也不在保存时做每文件幅度归一化。

v4增加正常发射机等效射频非理想模型，默认A，可手动切换B；没有指纹识别算法，也没有逐星硬件测量标定。不能仅凭PRN、随机种子或传播差异声称具有可验证的设备身份。切分出的文件仍属于同一次连续运行，不应自动视为独立采集批次来随机混分训练集和测试集。

## 8. 原有信号模型与文献依据

信号核心沿用v1：单颗假想MEO，默认PRN12，2.046 Mchip/s测距码、NH二次码、50 bit/s D1、BCH(15,11,1)及交织。按同一套量化星历计算轨道、发射时刻、地球自转、卫星钟差、简化大气传播、码/载波多普勒及幅度，叠加复高斯噪声和等效接收FIR。

默认参考天线32.06°N、118.79°E、高50m；BDT第1000周、接收SOW=240。它们属于假想正常场景，不是实测站址或历史广播回放。默认信号功率-158 dBW、滤波前C/N0=45 dB-Hz；65抽头Hamming窗FIR单边截止2.8 MHz，等效双边噪声带宽约5.508 MHz。它们是有说明的工程设置，不是规范对接收机的统一强制值。

主要原文：CSNO，**BDS-SIS-ICD-B1I-3.0，February 2019**。
https://en.beidou.gov.cn/SYSTEMS/ICD/201902/P020190227702348791891.pdf

- 第4.1/4.2节：信号结构、载频和信号特性。
- 第4.3节、表4-1：测距码和卫星抽头。
- 第5.1.3、5.2.1/5.2.2节：BCH、交织、NH和帧结构。
- 第5.2.3节、图5-8至5-11：D1字段和页面。
- 第5.2.4节：钟差、轨道、历书和UTC参数。

传播与噪声约定：

$$t_{code}=t-\frac{\rho+I+T}{c}+\delta t_s-TGD_1,$$

$$\tau_{phase}=\frac{\rho+T-I}{c}-\delta t_s,$$

$$\phi(t)=\phi_0-2\pi f_{B1I}\,[\tau_{phase}(t)-\tau_{phase}(0)].$$

$\rho,I,T$分别为几何距离、电离层与对流层延迟（米），电离层对载波相位与群延迟符号相反。噪声采用复双边PSD约定，每个实分量滤波前方差为 $N_0 f_s/2$。

$$N_0=\frac{C}{10^{(C/N_0)_{dBHz}/10}},\qquad B_{eq}=f_s\sum_k h^2[k].$$

平均频谱用无重叠Hamming窗口，按 $f_s\sum w^2$ 归一化。末尾不足一个FFT窗口的数据仍参加计算，计算中的FFT补点仅用于频谱分析，**不会补到原始文件中**。长时间平均频谱无法保留全部瞬时变化；代表时刻对比也不是全时间逐点频谱。

通用GNSS传播建模方法参考：
https://www.mathworks.com/help/satcom/ug/gps-receiver-acquisition-and-tracking-using-ca-code.html

载噪密度比关系参考：
https://gnss-sdr.org/docs/sp-blocks/tracking/

限制：单路等效发射分量，硬件模型有工程假设、不代表实际卫星功放或振荡器的测量复现；不含B1Q或其他卫星；没有AGC、量化、接收解调或授时解算；大气是开阔天空简化模型；有限采样/带宽不是全射频录波。

## 9. 验证状态

本次开发环境没有MATLAB/Octave。已做静态语法和独立Python数值/文件参考检查；**尚未在MATLAB R2024a执行本次v4代码或绘图**。请先运行随包自检，详细清单见 `VALIDATION.md`。

v4硬件测试见`TX_HARDWARE_zh.md`。v2及v3自检覆盖：PRN捕获及对照、已知延迟/多普勒恢复、不依赖真值的文件验证，以及非对齐计算块/分段边界、末段3个采样不补零、逐字节一致性、损坏文件识别、无完整文件读取、全段统计/频谱、I/Q绘图和PNG/FIG/MAT保存。

## 10. v4最常用硬件命令

```matlab
cfg=bds_default_config();                     % A，默认启用
% cfg.txHardware=bds_tx_hardware_profile('transmitter_B');
% cfg.txHardware.enabled=false;                % 原v3理想源
% cfg.txHardware.spurs.enabled=false;          % 仅关闭杂散
cfg.durationSeconds=5;
result=bds_generate(cfg);
% bds_tx_diagnostics(result.metadataFile);      % 手动，不自动执行
```

内部高率硬件计算增加运行时间，不额外保存高率IQ。总开关关闭直接走原计算路径；个别子模块关闭不等于关闭全部高率链路。详情见`TX_HARDWARE_zh.md`。
