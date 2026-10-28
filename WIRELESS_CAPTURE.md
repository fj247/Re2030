# 授时攻击：本地无线信号采集

当前优化分支：`feat/timing-wireless-ui-warmup`。上一版已验证版本保留为标签 `timing-wireless-v1`（`bc9ee49`）和原分支 `feat/timing-wireless-capture`。本功能仅接入变电站授时攻击场景，使用 MATLAB R2024a 生成仿真 I/Q，无 SDR 或实际射频发射。

## Windows 使用

在 `D:\2030\Re2030` 启动原来的 Python 服务：

```powershell
python main.py --ui --scenario scenarios/substation-live.json --output runs --port 8000
```

1. 加载“变电站授时攻击场景”，打开检测节点。
2. 首次使用勾选“启用无线采集”，填写 MATLAB 可执行路径和可写的绝对保存目录，保存设置。“浏览文件夹”和“打开本轮文件夹”操作的是运行 Python 服务的本地 Windows 电脑。
3. 显示“接收装置准备中”，随后显示“接收装置已就绪”。若已有启用的有效配置，加载场景后自动准备。
4. 就绪后在攻击节点手动开始攻击。准备中点击会提示“相关装置启动中，请稍后”，本次攻击不会启动，也不会延迟自动触发。
5. 首个 0.05 秒分片完整关闭后，独立进程开始分析；后续分片继续采集。平均功率谱先完成先显示，PRN 搜索图和相关峰局部切片随后显示。
6. 结束攻击或请求停止采集后，停止继续生成，收尾末片并校验全部分片。图表只分析首片一次。如果结束时首片未满 0.05 秒，就分析实际关闭的短片；不足 20 毫秒时只生成平均功率谱，提示 PRN 采样不足。
7. 下一轮攻击需等待本轮生成、收尾和分析全部完成。正常完成后两个工作进程保持常驻，无需重新启动 MATLAB。

仅浏览器绘制三张图，不再生成 I/Q 包络或 PNG 截图。悬停查看数值，滚轮缩放横轴，双击或按钮重置。采集状态轮询不重建已有图表，保留缩放。历史记录中的三张旧 PNG 仍可查看，I/Q 图不再展示。

## 准备和生命周期

- 启用配置并加载授时攻击场景后，启动生成、分析两个 MATLAB 常驻进程；两者均准备完成才报告就绪。独立分析避免阻塞持续采集，会比上一版增加一个进程的内存占用。
- 预启动只准备解释器、确定性的硬件滤波/相噪设计系数、PRN 和 FFT 等，不生成或保存攻击波形。设计缓存按全部输入配置匹配，每轮重新创建随机、滤波、导航及波形状态，不复用上轮信号。
- 点击开始后仍有每轮模型初始化和首块计算时间；未承诺实时生成速度或首片的固定到达时间。
- 未启用采集时不启动 MATLAB，原有授时攻击演示照常进行。
- 现实操作时间、实际信号长度、前端推演时间相互独立。推演暂停/加速不改变采集；结束攻击、停止推演、重建运行及关闭服务请求协作停止。重建运行需等采集收尾，但不必等待已开始的首片分析。
- 刷新浏览器不停止后台任务，右下角入口恢复本轮及历史记录；不自动重建场景或重启攻击。
- 更改配置/禁用采集需等待生成和分析完成。修改配置后重新准备；装置启动失败后可检查日志、再次保存设置重试。
- 正常关闭服务请求文件收尾和工作进程退出。不强杀写文件进程。服务意外退出后，工作进程通过 30 秒续期文件检查退出，生成在块边界停止；进程被强杀或机器断电仍可能留下 `.partial`。重新启动服务将未确认结束的历史任务标为中断。
- 每轮原始数据最多 2 GiB，另保留磁盘余量；不复制完整大文件。采样率 8.184 MHz，每复样本 8 字节，完整 0.05 秒分片为 409,200 复样本、3,273,600 字节（约 3.12 MiB）。仅改存储边界，不重置连续波形。

## 文件和信息边界

```text
capture_<任务ID>/
  detector/
    segment_000001.iq.f32   # 小端 float32 I0,Q0,I1,Q1,...，无头
    ...                    # 写入中的文件以 .partial 结尾
    manifest.json          # 全部采集收尾/校验后才就绪，含样本索引和 SHA-256
    mean_psd.json          # 首片全部实际数据的平均功率谱数值
    prn_search.json        # 首片起始 20 ms 延迟—多普勒相关搜索图数值
    correlation.json       # 同一次搜索的全分辨率局部峰值切片数值
    analysis.json          # 三张图各自状态、首片来源、PRN 证据及错误
  private/<本轮模型目录>/  # 配置、硬件 A、内部真值等，不作为识别输入
  first_segment.json       # 已关闭首片的内部读取快照，含私有配置
  analysis_request.json    # 内部分析请求，仅引用首片快照
  request.json
  progress.json
  generated.json
  generation.log
  analysis.log
```

`detector` 是后续识别输入目录，不含硬件 A、随机种子或模型真值；`manifest.json` 只列格式、采样率、操作时间、实际长度、连续分片索引、大小和 SHA-256。原始 I/Q 不通过浏览器下载；网页只访问白名单内的小型 JSON 和历史 PNG。首片图表完成不表示整轮识别数据已就绪，最终 `data_ready` 仍以全部文件校验为准。分析失败不撤销已通过校验的采集数据。

搜索图在数值计算完成后按码延迟分箱取最大值压缩至最多 512 列，降低传输和绘图开销；没有改变搜索算法、阈值和数值判定。精确峰位置单独保存，局部切片保持原采样分辨率。目标 PRN 及等效接收 FIR 用于原有结构诊断与对照，不读取发射端真值延迟、多普勒或硬件身份。

服务索引、设置和工作进程日志位于 `<--output>/.wireless/`。每次服务准备的工作进程使用独立会话目录 `workers/<会话ID>/{generation,analysis}/`，其中 `worker.log`、`launcher.log`、`startup_error.json` 用于启动诊断。每轮 `generation.log`、`analysis.log` 由常驻 MATLAB 的 diary 记录。

## 修改与验证

主要实现：Python `wireless_capture.py` 管理配置/首片监测/任务，`matlab_worker.py` 管理常驻进程与原子命令邮箱；MATLAB `bds_capture_worker.m` 等待任务，`bds_generate.m` 在首片关闭后发布内部读取快照，`bds_capture_analyze.m` 仅导出三份绘图数值，前端 `wireless-charts.js` 用 Canvas 绘图。没有新增工具箱依赖。

附件原始包 SHA-256：`cb14ce96f2ad013bc4485a0f5685c23a4fa754a2576b27a8a0d85395f503d258`，集成源码在 `matlab/beidou_b1i/`。

本地 MATLAB 检查（调整可执行路径）：

```powershell
& 'D:\Matlab\Matlab\bin\matlab.exe' -batch "addpath('D:\2030\Re2030\matlab\beidou_b1i'); test_bds_capture_control; test_bds_capture_first_segment; test_bds_capture_worker"
```

分别检查停止/末片及首片发布、连续分片/首片读取边界/三张数值图、常驻工作循环连续接受两轮命令和退出。不需要导出图像，数值图也不需要 MATLAB 图形窗口。正常波形生成、双 MATLAB 并发启动、首片分析速度和 Windows 原生目录窗口仍须本地实测。

云端验证：

```text
python -m unittest discover -s tests -p test_wireless_capture.py
python -m unittest discover -s tests -p test_matlab_worker.py
node --test tests/*.cjs
```

云端没有 MATLAB，进程/浏览器联调使用明确的测试替身，不能据此宣称 MATLAB 实测通过。全量 Python 回归目前有两个与本改动无关的 GOOSE 导入文件校验错误（`communication-log.jsonl`），需单独处理。
