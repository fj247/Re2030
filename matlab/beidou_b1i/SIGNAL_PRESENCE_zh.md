# 从保存的I/Q验证北斗B1I信号存在性（v3）

本功能只在SDR数字基带层面进行PRN相关捕获，不改变原始波形，不增加硬件指纹，不解码导航电文或计算授时结果。

## 1. 最简单的调用

在运行脚本后，MATLAB工作区仍有 `result` 时：

```matlab
evidence=bds_validate_signal(result.metadataFile);
```

已有上一版生成的数据也可以直接分析，无需重新仿真。将路径换成你的实际JSON：

```matlab
evidence=bds_validate_signal('bds_output/本次运行目录/b1i_single_normal.json');
```

支持v1完整单文件与v2分段索引。默认选择开头、中间、结尾三个位置，每处读取20毫秒；短记录不足以提供三个不同起点时会自动去重。它不分析整段每一个时刻，也不会自动在每次仿真结束后执行。

## 2. 结果图怎么看

手动调用后，生成一个四联图，并在本次运行目录中创建独立的 `signal_validation_时间戳` 子目录。

| 面板 | 含义 |
|---|---|
| 左上 | 第一个时间片的目标PRN码延迟—多普勒相关搜索图；红叉是最强候选点 |
| 右上 | 候选多普勒处、峰附近±20码片的循环放大切片，标出近似门限及峰值；标题显示峰与竞争峰之比、检测结果 |
| 左下 | 多个目标时间片、其他PRN及纯噪声的峰值与近似门限对比；最终判据还包含峰比，不只比较柱高 |
| 右下 | 多个时间片中估计的记录相对码周期边界和粗多普勒；观察候选参数随时间的变化 |

相关搜索图的横轴是**码延迟**，不是时间，纵轴是多普勒假设；它不是STFT时频功率矩阵。

码延迟只有一个1毫秒周期内的相对含义。右下图将每个时间片的起始时间也计入，显示相对于整段记录的码周期边界相位，仍按1毫秒取模。出现跨0/1000微秒的跳变可能只是取模，不一定是信号异常。这些量都不是电文帧起点或绝对传播时延。

## 3. 保存哪些结果

- `signal_presence.png`：四联图。
- `signal_presence.fig`：可在MATLAB重新打开的图。
- `signal_presence.mat`：完整数值报告，包括每个目标时间片的搜索矩阵。
- `signal_presence.json`：精简报告，记录峰值、门限、峰比、参数估计、对照结果及限定条件，不包含大型矩阵。

数值结果先保存，再尝试图形输出。若图形环境失败，报告中会有 `plotStatus='failed'` 和 `plotError`，已有数值结果仍保留。

```matlab
evidence.evidenceStatus
evidence.probes{1}.peakScore
evidence.probes{1}.nominalThreshold
evidence.probes{1}.peakToCompetitorRatio
evidence.probes{1}.dopplerHz
evidence.probes{1}.codeDelayChips
evidence.otherPrn.detected
evidence.noiseDetectionCount
```

## 4. 如何理解判定

每个时间片要求同时满足：

1. 归一化相关峰超过近似搜索门限。
2. 峰值与排除码延迟主峰附近后、最强竞争峰之比不低于默认1.4。

排除主峰附近时，会排除所有多普勒行中距离候选码延迟2码片内的点。这是避免把同一主峰在邻近多普勒处的响应当成独立竞争峰。1.4是工程筛选值，不是北斗规范规定值。

所有选定时间片通过、其他PRN未通过、所有纯噪声对照未通过，且目标候选不在多普勒搜索边界时，整体状态为：

```text
supported_in_tested_windows
```

它表示“该诊断搜索在选定I/Q窗口中支持目标PRN结构存在”。其余情况返回 `inconclusive`（证据不足），**不自动解释为信号不存在或代码生成错误**。应检查搜索范围、采样率、积分长度、信号强弱和对照情况。

## 5. 无需真实时延/多普勒的搜索

检测核心 `bds_acquire` 只接收I/Q、采样率、待搜索PRN及搜索设置。不接收真实码延迟、真实载波相位、真实多普勒、星历或电文。

上层读取元数据中的格式、配置PRN（可手动指定）和已知等效接收滤波器。滤波器仅用于生成频带相近的纯噪声对照。纯噪声强度根据第一个实际I/Q时间片测得的总功率缩放，不使用配置的C/N0、信号功率或仿真噪声种子。

不会打开 `_truth.mat`，也不会把真值中的正确峰位置拿来作为搜索答案。测试会故意提供不存在的真值文件和不可用的时延/钟差元数据，检查验证模块能够独立运行。

## 6. 对NH码/电文翻转的处理

每1毫秒输入分成前后两个0.5毫秒半块，分别与周期PRN进行FFT循环相关，再把两个半块和多个毫秒的相关幅度平方相加。默认总跨度20毫秒。

这不是直接把20毫秒当成一段做相干相加。分半与非相干积累可以减轻NH码或数据符号翻转造成的抵消；半块内部仍可能发生翻转，因此会有灵敏度损失。它不是完整NH同步、载波跟踪或导航比特恢复器。

多普勒假设 $f$ 下，对第 $m$ 个1毫秒块、半块掩码 $g_h[n]$，计算：

$$R_{m,h}(\ell,f)=\sum_n x_m[n]g_h[n]c[(n-\ell)\bmod N]e^{-j2\pi fn/f_s},$$

$$P(\ell,f)=\sum_m\sum_{h=1}^2|R_{m,h}(\ell,f)|^2.$$

这里 $c$ 是标准PRN本地副本；不需要知道实际的导航电文比特。FFT仅加速上述循环相关。

## 7. 门限的重要限定

噪声下，独立同方差复高斯相关输出的幅度平方和可用Gamma分布描述。本实现以形状参数 $K=2M$ 的Gamma模型作参考，用搜索平面的中位数估计背景均值，再按搜索单元数量作Bonferroni门限设置。

**实际数据有带限噪声，搜索单元之间也相关，半块输出可能相关，背景也是估计量。因此这是近似门限，不是经过标定的严格CFAR/Pfa保证。** `nominalSearchPfa=1e-3`仅控制该参考门限，不能报告为实际虚警率已达到0.1%。峰比判据又加入了一项工程筛选。

默认三次纯噪声对照只能作为有限诊断证据，不足以测出如此小的虚警率。若未来要研究检测概率/虚警率，应独立进行大量噪声试验并分析置信区间，而不是把几次未检出称作零虚警。

## 8. 可调整设置

```matlab
o=bds_acquisition_options();
o.targetPrn=12;
o.controlPrn=13;
o.probeStartSeconds=[0 1 2];
o.dwellMilliseconds=20;
o.dopplerMinHz=-10000;
o.dopplerMaxHz=10000;
o.dopplerStepHz=500;
o.noiseTrials=3;
evidence=bds_validate_signal(result.metadataFile,o);
```

只保存结果和图、不显示窗口：

```matlab
evidence=bds_validate_signal(result.metadataFile,struct('showFigure',false));
```

只计算、保存数值，不生成图：

```matlab
evidence=bds_validate_signal(result.metadataFile,struct('plotResults',false));
```

只返回数值，不写任何结果文件或打开窗口：

```matlab
o=struct('saveResults',false,'showFigure',false,'plotResults',false);
evidence=bds_validate_signal(result.metadataFile,o);
```

其他PRN对照默认使用相邻的另一个受支持PRN，建立在当前单卫星仿真的前提上。对真实多卫星录波，其他PRN可能真的存在，不能原封不动沿用“其他PRN不应检出”的整体判定。

此版本要求每毫秒采样数为偶整数，不进行捕获重采样；默认8.184 MHz满足要求。扩大多普勒范围、加密步长、增加时间片或对照数都会增加运算量。过长非相干积累会受码多普勒漂移影响，因此默认20毫秒，不能把增加积累时间当成无代价改进。

## 9. 文献与验证状态

- 北斗官方B1I ICD3.0，第4.3节：PRN码；第5.2.1节：NH二次码。
  https://en.beidou.gov.cn/SYSTEMS/ICD/201902/P020190227702348791891.pdf
- GNSS-SDR官方Acquisition文档：码相位/多普勒搜索、FFT相关、积累和门限检测的基本框架。
  https://gnss-sdr.org/docs/sp-blocks/acquisition/

本实现为独立的诊断捕获器，不声称与GNSS-SDR检测器和门限完全相同。它的证据不能替代导航电文恢复、BCH校验或发射设备身份验证。

当前环境无MATLAB。新增代码已做静态语法检查；独立Python参考测试验证了含NH/数据翻转、滤波与低SNR的三个信号样例，目标PRN检出，其他PRN与纯噪声未检出；十次额外噪声诊断未检出。**这些不是交付MATLAB代码的执行结果，也不是精确虚警率证明。** 详情在 `VALIDATION.md`。

本机运行新增自检：

```matlab
test_bds_acquisition
```

不测图形保存：

```matlab
test_bds_acquisition(false)
```

总自检 `test_bds_simulator` 也已包含此项。
