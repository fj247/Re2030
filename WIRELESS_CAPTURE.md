# 授时攻击：本地无线信号采集

本功能位于 `feat/timing-wireless-capture`，只在“变电站授时攻击场景”中把手动攻击操作接到 MATLAB 波形生成。原授时／差动保护演示继续按原逻辑工作。没有 SDR 控制或真实射频发射。

## Windows R2024a 使用

1. 在仓库根目录使用原命令启动 Python 服务，例如：

   ```powershell
   python main.py --ui --scenario scenarios/substation-live.json --output runs --port 8000
   ```

2. 加载“变电站授时攻击场景”，点选攻击节点附近的检测节点。
3. 勾选启用无线采集，填写 MATLAB R2024a 的完整可执行路径，例如 `C:\Program Files\MATLAB\R2024a\bin\matlab.exe`。程序会尝试检测该默认安装位置，非默认位置需自行填写。
4. 选择可写的本地绝对保存目录，例如 `D:\2030\captures`，点击保存设置。“浏览文件夹”使用本机 Windows 目录选择窗口，可能出现在浏览器后方。
5. 在攻击节点点击“开始攻击”。MATLAB 异步初始化和计算，检测面板实时显示排队、初始化、采样及分片文件状态。MATLAB 启动和模型初始化可能耗时，并不代表已产生样本。
6. 点击“结束攻击”后停止继续生成；程序完成最后一片、校验和索引，然后排队分析。检测面板也有单独“请求停止采集”按钮，只停止采集，不更改已在进行的授时演示攻击。
7. 点“打开本轮文件夹”可在运行 Python 的 Windows 电脑上打开检测目录。原始 I/Q 不通过浏览器传送；图像和小型 JSON 可在面板查看。

检测默认关闭，不启用时无需 MATLAB。启用时如果路径、MATLAB 或磁盘预检失败，本轮带采集的攻击不会被静默启动。进程启动、许可或运行失败会显示错误，详细日志在本轮检测目录的上级 `generation.log` / `analysis.log`。

## 时间和生命周期

- 使用现实中的开始／结束操作控制生成，与推演倍速无关。现实操作时长包括启动、排队和计算，独立于实际生成的信号时长。
- 暂停推演不会停止采集；停止推演、结束攻击或重建运行会请求停止。重建运行时，如原采集仍在收尾，页面会提示稍后再次加载，不会直接丢弃旧任务。
- 停止采用方案 A：只保留实际已生成的样本，不补算至操作时间差。每轮默认每段 1 秒信号，末段可短于 1 秒，无填零。
- 正常停止在计算块边界处理；单块的信号长度不等于计算耗时，不能保证毫秒级停止。初始化中结束可能没有有效样本，显示“未产生有效采样”。
- 刷新浏览器不终止后台进程。页面右下角“检测任务”入口可以恢复查看已有任务、请求停止。
- 关闭 Python 服务会发送停止请求并等待一段收尾时间。强制结束系统进程仍可能留下不完整文件；服务重新启动时旧活动任务标为中断，并发送协作停止标记，不宣称这些数据已完成。
- 同时只接受一个生成任务。图表独立排队，整个服务同时最多启动一个 MATLAB 进程，因此遇到上一轮分析正在占用资源时，新生成任务会显示“等待计算资源”。已经通过校验的数据无需等待图表完成即可用于后续读取。
- 每轮原始采样预算为 2 GiB，并为磁盘保留余量；接近预算时请求正常收尾，检测面板提示限制原因。默认复采样每秒约 65.47 MB，不保留重复的完整大文件。

## 保存目录与信息边界

每轮独立 `capture_<任务ID>/`：

```text
capture_<id>/
  detector/
    segment_000001.iq.f32
    ...                     # 在写文件以 .partial 结尾
    manifest.json           # Python 校验后才生成
    overview.png            # 全程 I/Q、功率与频谱
    presence.png            # PRN 搜索及对照证据
    correlation.png         # 相关峰局部切片
    analysis.json           # 数值摘要／图表失败／采样不足等状态
  private/<本轮模型目录>/   # 配置、发射机 A、真值、设计及原始分析资料
  request.json
  progress.json
  generated.json
  generation.log
  analysis.log
```

`detector` 是提供给后续识别程序的目录。`manifest.json` 只有格式、采样率、请求／停止时间、实际样本数、信号时长，以及连续分片的名称、起始采样、长度、字节数和 SHA-256。没有发射机身份、硬件 A 参数、随机种子或内部真值。分片本身只保存一次；模型内部索引通过独立分片目录读取这些文件，不另复制整套 I/Q。

Python 服务的任务和设置索引位于 `runs/.wireless/`（相对于启动时的 `--output`），不要把它与原始采样目录一起当成射频指纹输入。服务重启后从该索引恢复历史任务。

“数据就绪”表示文件收尾和校验已通过，与“图表完成”分开。图表失败不撤销已经完成的数据；数据不足 20 ms 时不执行默认 PRN 搜索，也不伪造相关峰。

图表从保存的 I/Q 读取计算。目标 PRN 是预配置搜索目标；相关峰只能说明所检窗口是否支持匹配码结构，不代表攻击者身份识别、导航电文解码或真实接收机授时欺骗已成功。

## MATLAB 修改及本地验证

附件原始包 SHA-256：`cb14ce96f2ad013bc4485a0f5685c23a4fa754a2576b27a8a0d85395f503d258`。源码保留在 `matlab/beidou_b1i/`。扩展内容：

- `bds_generate.m`：可选的协作停止／容量检查、进度、实际样本数收尾；不带 `captureControl` 的原入口保持固定时长模式。
- `BdsFileWriter.m`：支持按实际长度完成最后一片，直接向检测目录写入；读取和校验函数支持独立分片目录，原用法兼容。
- `bds_capture_entry.m`：默认硬件 A，关闭完整文件，写独立仿真资料目录。
- `bds_capture_analyze.m`：从分片读取、生成概览和相关证据；只导出检测需要的图和摘要。
- `bds_capture_stop.m`：按成功写入的样本账本判断容量，不依赖 Windows 打开文件的目录大小刷新。
- `test_bds_capture_stop.m`：不生成波形即可检查容量边界和停止标记。
- `test_bds_capture_control.m`：短任务停止／容量收尾、末段、分片读回及零样本测试，包含上述边界测试。

在仓库根目录的 PowerShell 执行：

```powershell
& 'C:\Program Files\MATLAB\R2024a\bin\matlab.exe' -batch "addpath('matlab/beidou_b1i'); test_bds_capture_control"
& 'C:\Program Files\MATLAB\R2024a\bin\matlab.exe' -batch "addpath('matlab/beidou_b1i'); test_bds_simulator(false); test_bds_storage(false)"
```

再在界面做一次短采集，结束后核对 `manifest.json`、分片、概览和相关峰。目录选择、打开资源管理器和 MATLAB 绘图也必须在 Windows 上实际验证。

云端没有 MATLAB：Python 单元测试使用明确的进程替身验证任务控制与数据契约，浏览器也用测试进程验证面板、刷新恢复、停止、数据就绪和不足样本提示。这些结果**不能替代 MATLAB 波形与图像实测**，未将 MATLAB 测试标成已通过。

Python／JavaScript 回归：

```powershell
python -m unittest tests.test_wireless_capture -v
python -m unittest discover -s tests -t . -v
node --test tests/*.cjs
```
