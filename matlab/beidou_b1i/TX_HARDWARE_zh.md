# v4：正常卫星发射机的等效射频非理想模型

本版本不实现射频指纹提取、训练或分类，不根据设备可辨性调整参数。每次运行只选择一个硬件配置、一颗卫星；所有设备参数在本次运行中保持固定。A/B均为虚拟正常工作参考，不是两颗真实北斗卫星的实测复现。

## 1. 最短使用流程

在解压后的代码目录执行，避免旧版同名函数留在路径：

```matlab
clear classes
addpath(pwd)
cfg=bds_default_config();          % 默认开启硬件模型，配置A
cfg.durationSeconds=5;
cfg.segmentSeconds=1;
cfg.keepFullFile=true;
result=bds_generate(cfg);
evidence=bds_validate_signal(result.metadataFile); % 手动，仍然只验证PRN结构
```

运行前切换B（仅切换硬件，卫星PRN/场景仍由cfg其余字段决定）：

```matlab
cfg=bds_default_config();
cfg.txHardware=bds_tx_hardware_profile('transmitter_B');
cfg.durationSeconds=5;
result=bds_generate(cfg);
```

一次关闭全部发射机硬件非理想：

```matlab
cfg.txHardware.enabled=false;
result=bds_generate(cfg);
```

总开关关闭直接走原v3理想源路径，不增加硬件重采样、功率标定或硬件延迟。传播、噪声和原接收FIR继续工作。对合法配置，A/B名称与各子模块设置都不会影响关闭后的数据。没有txHardware字段的旧配置也按理想源处理。

注意：`run_bds_simulation`是脚本，会clear并重新创建cfg。需要手动配置时使用上述`bds_generate(cfg)`流程，或者直接修改脚本，不要在终端设置cfg后再运行该脚本。

## 2. 开关与参数

| 开关 | 默认 | 主要参数 |
|---|---|---|
| `cfg.txHardware.enabled` | true | 总开关 |
| `.bandwidth.enabled` | true | `cutoffHz=8e6`，固定二阶Butterworth |
| `.response.enabled` | true | `amplitudeRipplePpDb`、`groupDelayRipplePpSeconds`、`referenceBandHz` |
| `.pa.enabled` | true | `smoothness`、`inputBackoffDb` |
| `.pa.ampmEnabled` | true | `ampmAtReferenceDeg`；受pa.enabled控制 |
| `.phaseNoise.enabled` | true | `offsetHz`、`historicalLevelDbcPerHz`、`marginDb` |
| `.spurs.enabled` | true | 等长的`offsetHz`、`levelDbc`、`phaseRad`向量 |
| `.iqImbalance.enabled` | false | `amplitudeDb=0.1`、`phaseDeg=0.5` |
| `.edgeAsymmetry.enabled` | false | `fallingEdgeDelaySeconds=1e-9` |
| `.timingJitter.enabled` | false | `rmsSeconds=0.1e-9`、`correlationSeconds=0.001` |

例如只关闭杂散，或修改功放工作点：

```matlab
cfg.txHardware.spurs.enabled=false;
cfg.txHardware.pa.inputBackoffDb=8;
```

`.extraCarrierOffsetHz=0`与`.extraLossDb=0`也是可调字段，受总开关控制。它们默认不额外叠加已有的钟漂、几何多普勒和功率预算。

有限带宽关闭时数值抗混叠滤波仍保留；它不是另一个卫星硬件模块。全部子模块关闭但总开关仍开时，也仍经过高率DAC与重采样，不能当作原版逐字节基准；逐字节基准应关闭总开关。

## 3. 两套默认参数与来源

| 参数 | A（默认） | B |
|---|---:|---:|
| 单边-3dB发射截止频率 | 8 MHz | 8 MHz |
| 额外幅频起伏目标峰峰值 | 0.05 dB | 0.04 dB |
| 额外群时延起伏目标峰峰值 | 1 ns | 0.8 ns |
| Rapp平滑参数p | 2 | 2 |
| IBO | 6 dB | 7 dB |
| 标称输入幅度处AM/PM | 1° | 0.8° |
| 历史相位噪声谱的下移裕量 | 10 dB | 12 dB |
| 单音杂散 | -70 dBc | -74 dBc |
| 杂散偏移 | +0.8 MHz | +0.8 MHz |

两套参数的资料性质：

- CSNO ICD 2.0（2013）4.2.4给出10/100/1000/10000/100000 Hz处的-60/-75/-80/-85/-95 dBc/Hz谱点；4.2.7给出B1I全宽16 MHz的3dB带宽。这是历史指标参考，不是现在逐星测量。默认10/12 dB裕量、Butterworth拓扑属于假设。
- 陈颖等（2022）表3报告带内杂散MEO -78.26 dBc、IGSO -64.38 dBc。A/B的-70/-74 dBc只是参考该量级选取，不是统计分布；位置、数量、相位为假设。
- Rapp AM/AM、幅相转换属于通用模型；p、IBO、相移、额外幅频及群时延起伏均是工程假设。
- B1I ICD 3.0（2019）的相位噪声要求与三阶10Hz单边带宽PLL有关。本程序不实现该PLL，不宣称通过规范符合性验证。
- 未使用畸变/故障威胁空间当作正常器件参数范围，也不根据相关损耗或识别结果反向扩大损伤。

参考原文：

1. CSNO. BDS SIS ICD 2.0, December 2013, 4.2.4/4.2.7。大学托管原文：<https://gge.ext.unb.ca/Resources/beidou_icd_english_ver2.0.pdf>
2. CSNO. BDS-SIS-ICD-B1I-3.0, February 2019：<https://en.beidou.gov.cn/SYSTEMS/ICD/201902/P020190227702348791891.pdf>
3. 陈颖、卢鋆、刘成等. 北斗卫星导航系统国际民航标准重点问题研究与指标验证. 天文研究与技术,2022,19(5):447–457：<https://html.rhhz.net/Jwk_twyjyjs/html/20220506.htm>
4. MathWorks功放模型：<https://www.mathworks.com/help/comm/ref/comm.memorylessnonlinearity-system-object.html>
5. MathWorks相位噪声模型：<https://www.mathworks.com/help/comm/ref/comm.phasenoise-system-object.html>
6. Hegarty & Ross, Initial Results on Nominal GPS L5 Signal Quality, ION GNSS 2010,935–942：<https://www.ion.org/publications/abstract.cfm?articleID=9210>。其中所述最高约5ns码边沿不对称是GPS C/A观测，不是B1I典型值。本程序可选边沿参数不是B1I实测。

## 4. 数学定义与等效位置

硬件在均匀的发射码时钟轴上生成，不把传播载波相位、距离损耗或接收热噪声送入功放。处理顺序：

1. PRN/NH/D1组合，矩形DAC的高率采样单元积分；可选下降沿位移及数字码时序抖动。
2. 二阶Butterworth发射低通。
3. 可选I/Q支路模型：I乘g、Q除g，g=10^(amplitudeDb/40)，Q支路正交误差phaseDeg。只有单路实B1I输入时部分IQ效应会退化或消失，程序不人为构造另一分量。
4. Rapp AM/AM及可选平滑AM/PM。
5. 输出通道的额外平滑幅频/群时延响应。
6. 固定标定、发射相位噪声、可选弱杂散、额外频偏/损耗。
7. 数值抗混叠FIR；降到16.368 MHz中间轴；窗化sinc插值到实际接收采样所对应的发射时刻；再加传播载波相位、距离幅度及接收噪声，执行原接收FIR。

### 功放

归一化标称输入幅度r_ref=1，A_sat=10^(IBO/20)。

$$A(r)=r[1+(r/A_{sat})^{2p}]^{-1/(2p)}.$$

$$\phi_{PA}(r)=\phi_{ref}\frac{2(r/r_{ref})^2}{1+(r/r_{ref})^2}.$$

IBO是相对这个固定标称输入功率的回退量；带宽滤波后的实际平均工作点可略有不同。不是把极小的接收端瓦特幅度直接送入未定标的卫星功放。

恒包络输入可能只产生固定增益/相位，属正常结果；不为生成指纹加入额外记忆多项式。滤波器已使整条链路具有记忆，但不代表真实功放所有记忆机理。

### 输出通道响应

在B=2.046 MHz参考范围定义目标平滑形状：

$$T(f)=\exp[-(f/(2B))^8],$$
$$A_{dB}(f)=\tfrac{R_{pp}}{2}\cos(\pi f/B)T(f),$$
$$\phi(f)=-\tau_{pp}B\sin(\pi f/B)T(f).$$

频率采样后IFFT、Blackman截断并作DC增益标定，形成实系数因果FIR。`firLength=257`指65.472 MHz下的长度，改变内部采样率时按相同物理支持时长缩放。实际峰峰值与目标存在截断误差，诊断报告实际系数的结果，不能将目标值伪称实测。

### 相位噪声

12个独立、零均值、平稳AR(1)过程叠加，独立RandStream；角频率参数由cornerHz确定。在1.048576 MHz随机过程时钟上生成，线性插值到发射轴。通过非负相对PSD拟合，使单边相位PSD满足S_phi,one-sided=2*10^(L/10)，拟合计入插值器sinc^4响应。

与方案讨论中的“直接逐点插值并延拓谱线”不同，实现采用有状态AR混合，避免为10Hz相位噪声在65MHz上使用数百万抽头FIR。实际谱为Lorentzian混合，两端自然延拓并在随机过程Nyquist附近受限，不声称严格复制指定谱线；每轮保存拟合误差、实际系数和理论RMS。这是可解释的近似，需要时可调整cornerHz重新拟合；不采用独立逐采样随机相位。

可选timingJitter为独立平稳OU数字码时序过程，RMS和相关时间明确；不是再次注入公共卫星钟差，也不是白噪声式跳变。

### 固定时延与功率

线性TX滤波器及数值AA的DC群时延从输出时刻参考中去除，以免重复计算NAV的TGD；频率相关波形变形仍保留。AM/PM固定相移不作为TGD移除。

每轮用固定8ms PRN参考、丢弃前4ms启动过程，标定确定性主信号的平均功率为1。标定在AA/接收滤波前定义，PN/杂散不参加；整个运行只使用一个标量。配置signalPowerDbW仍决定参考距离下的标称主分量功率。AA/接收滤波损失及额外损耗不会被逐块抵消，接收N0不随硬件更换而自动重算。最终measuredSignalPowerW包含弱杂散，不可误称只含有用载波。

## 5. 计算精度、随机过程与连续性

- 默认输出8.184 MHz，内部倍数8，即65.472 MHz。可设16/32做收敛检查。不是固定精度保证。
- 源采用高率采样单元积分而非整点移动，可表示小于一个内部采样周期的边沿位移；仍是有限率近似。
- AA采用Blackman窗FIR，通带目标到接收截止2.8 MHz，阻带从输出Nyquist 4.092 MHz开始；中间采样与48邻点Blackman窗sinc插值用于发射时刻映射。
- 内部65536点计算块固定，不受cfg.blockSamples和segmentSeconds影响。改变internalBlockSamples会改变FFT舍入（可产生末位差异），但不应该改变物理模型；它不作为设备标识。
- 相位噪声及抖动使用独立随机流、固定4096点随机块和平稳初态；接收噪声继续使用原cfg.randomSeed，不被TX随机数消耗。
- `cfg.txHardware.seed`控制同一硬件随机实现；换种子不是换设备。A/B默认同种子，防止用种子编码设备身份。
- 同次运行只切换文件，无归一化、补零、状态重置、文件起停瞬态。
- 开启高率链路显著增加计算量但不增加默认IQ文件采样率；先运行0.04秒自检或0.1秒排错，再运行5秒，不要用完整60秒排错。

## 6. 保存/加载硬件配置

```matlab
p=bds_tx_hardware_profile('transmitter_A');
p.name='my_transmitter';
p.pa.inputBackoffDb=8;
bds_tx_save_profile('my_transmitter.json',p);

cfg=bds_default_config();
cfg.txHardware=bds_tx_load_profile('my_transmitter.json');
cfg.durationSeconds=5;
result=bds_generate(cfg);
```

JSON为完整结构。版本、字段及参数边界严格校验；不静默接受拼错字段。辅助保存/加载按默认接收频率验证，实际运行还按cfg的采样率重新验证。

每轮目录新增：

- `tx_hardware_profile.json`：本次实际配置、版本、来源与假设。
- `tx_hardware_design.json`：实际滤波器系数、时延参考、固定标定、PN拟合及说明；总开关关闭时记录原版旁路。
- 主JSON中的`configuration.txHardware`和`txHardware.effectiveModules`：包括父开关遮蔽后的实际启用状态。
- truth MAT中增加`txDesign`。文件索引和原始IQ格式保持兼容。

只保存配置名称是不够的；本程序保存完整修改后的值。

## 7. 手动诊断与测试

```matlab
[r,fig]=bds_tx_diagnostics(result.metadataFile);
```

打开模型曲线并将PNG/FIG/MAT保存到本轮目录。六图为线性TX幅频、因果群时延、AM/AM、AM/PM、PN理论PSD拟合、数值AA响应。诊断来自实际系数，不是从低SNR接收数据中估计出的卫星硬件参数，也不是识别结果。报告还给出额外响应实际峰峰值、AA阻带衰减。

```matlab
test_bds_tx_hardware(false)       % 数值与短文件，不测试图形
test_bds_tx_hardware(true)        % 增加模型曲线绘图
r=bds_tx_convergence()            % A/B确定性链路8x/16x对32x
% 或完整自检（包含旧版和硬件测试）
test_bds_simulator(false)
```

收敛检查关闭PN/杂散/抖动，避免将随机实现差异误判为采样误差；检查默认PA、响应与DAC。它只是一个数值夹具，不是所有场景的精度证明。扩大接收带宽、增强非线性或启用纳秒效应后，应另做收敛检查。

## 8. 明确限制

单路B1I等效模型不包含完整B1Q/其他分量共同经过功放时的全部互调；无真实载荷测量的系数反演；无温度/老化模型、接收机硬件损伤或PLL规范符合性验证。默认关闭的模块有可执行模型，但启用并不表示已证明真实B1I具有相应数值。所有设置可用于受控仿真，不能仅凭参数表声称真实卫星复现或指纹可辨。

当前开发环境无MATLAB/Octave；静态检查及Python独立数值检查不等价于MATLAB执行。请先在R2024a执行上述测试，失败时保留完整报错。本次不提供射频发射或分类器功能。
