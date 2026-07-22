# Catapult v3 设备验证状态

本文记录当前这张 Microsoft Catapult v3（Longs Peak，本文称为 `board 2`）的本地验证状态，以及下一阶段的板级验证安排。

状态定义：

- **本地已验证**：已经在当前物理卡上得到可重复的硬件结果。
- **准备验证**：社区已有引脚或参考工程，本仓库将使用 Quartus Prime Standard 22.1 重新生成、编译并在当前卡上验证。
- **暂时不好验证**：缺少主机布线、另一端设备或测量仪器，或者现有资料不足以安全驱动相关引脚。
- **社区已验证**不等于本地已验证；社区结果只作为引脚和参数的技术依据。

## 当前硬件和工具基线

| 项目 | 当前值 |
| --- | --- |
| 板卡 | Microsoft Catapult v3 PCIe variant（Longs Peak），`board 2` |
| FPGA 工程目标 | `10AXF40AA` |
| FPGA JTAG ID | `0x02E060DD` |
| Quartus | Prime Standard 22.1std.0 Build 915 |
| JTAG | `JTAG-MPSSE-Blaster [00 Single RS232-HS]` |
| JTAG TCK | 插件报告 `15M` |
| 配置 Flash | Quartus 识别为 `MT25QU01G`，Examine silicon ID `0x21` |
| 当前 Flash 上电设计 | `pcie-temp-demo` |
| 当前 SRAM 设计 | `board-validation/i2c`（后续验证会继续替换） |
| 当前主 PCIe 端点 | `1172:e003`，最近枚举地址 `0000:6a:00.0` |

## 本地已验证

### USB、JTAG 和 SRAM 配置

- 板载 FT232H 能以 USB High-Speed 枚举。
- JTAG 链稳定识别 `0x02E060DD`；当前再次只读枚举成功，TCK 为 `15M`。
- `10AXF40AA` 目标可由 Quartus 22.1 完成综合、布局布线、汇编和时序分析，并能被当前器件接受。
- 已完成约 36.7 MB 的完整 SOF SRAM 下载；已知良好 LED smoke-test SOF 的 SHA-256 为 `f68641e9f89ff9e6db94c24d9dfd23a6db5b79ca4024a4aa9b23c7960717023e`。
- 完整 SRAM 下载后曾连续完成 20 次 JTAG IDCODE 扫描。

这里验证的是配置链路和基本设计运行能力。新的 I/O smoke 工程又完成了 9 个 LED 位的数字逐位控制；物理灯位和视觉极性仍需人工观察记录。

### LED、板载时钟和安全输入

- `board-validation/io-smoke` 已用 Quartus 22.1 对 `10AXF40AA` 完整编译，0 errors、5 warnings，并通过 SRAM 配置。
- SOF SHA-256 为 `85f800b9e8518dc0230ed6c06d11c876f366b0cdfacbc97211e593ac2481468d`。
- Timing Analyzer 报告 setup/hold 完全约束；setup、hold、recovery/removal 和 pulse-width slack 均非负。
- 以 U59 100 MHz 为参考，实测 Y3/Y4 分别为 `266.666883`/`266.667073 MHz`，Y5/Y6 分别为 `644.529394`/`644.530155 MHz`。
- 9 个 LED 位的全部独热和独低模式共 18 组均由 FPGA 探针回读一致，证明 9 位可独立数字控制。
- J11 的 `A24`、`A25`、`A26` 均保持输入；无外部激励时采样为 `0b000`。
- 详细构建、时序和实测记录见 [board-validation/io-smoke/RESULTS.md](board-validation/io-smoke/RESULTS.md)。

目前仍需人工观察正在运行的逐灯脚本，才能记录 LED 位到物理位置的映射和实际发光极性；J11 也需要 1.8 V 安全外部激励才能验证排针连续性。这两项不能仅靠 FPGA 探针代替。

### 两条 FPGA I2C 总线

- `board-validation/i2c` 已用 Quartus 22.1 对 `10AXF40AA` 完整编译，0 errors、9 warnings，并通过 SRAM 配置。
- SOF SHA-256 为 `c0f35d8d3f8f204b4dcd7a6b4cfee05de64cfb6f9cbdd772d4f2e21a9849e52a`。
- Timing Analyzer 报告 setup/hold 完全约束；最差 setup 为 `+5.456 ns`，最差 hold 为 `+0.016 ns`，其余 recovery/removal 和 pulse-width slack 均为正。
- channel 1（`K20/L20`）两轮稳定响应 `0x22`，与 DS250DF810 retimer 资料一致。
- channel 2（`J23/K21`）两轮稳定响应 `0x0c 0x1f 0x27 0x40 0x42 0x4c 0x51 0x6d`。
- TMP411 由 MFR ID `0x55`、device ID `0x12` 明确识别；本次本地/远端温度约为 `35.000 C` / `43.125 C`。
- `0x27` 读回 PCA9535 配置页 `ff ff`，身份得到强支持；`0x51` EEPROM 和 `0x6d` PCIe 时钟缓冲器与 BOM/数据手册地址相符。
- `0x0c`、`0x1f`、`0x40`、`0x42` 暂不强行命名；`0x40` 稳定 ACK，但 NACK LM25066 必须支持的 `MFR_ID(0x99)` 和 `CAPABILITY(0x19)`，另两个只读命令只返回全 `ff`，因此不能标为正常 LM25066；`0x42` 的 MFR_ID 路径也只返回全 `ff`。
- 扫描不写目标数据；定向 ID 脚本只选择只读指针/命令，没有写目标配置值。最终两路均为空闲高，FPGA OE 为 0。
- 详细构建、地址证据、Intel `BUS_HOLD` 根因和一次开漏恢复记录见 [board-validation/i2c/RESULTS.md](board-validation/i2c/RESULTS.md)。

本次没有发现常见地址 `0x50` 的 QSFP EEPROM，说明当前模块/线缆管理面尚不能标记为本地通过；retimer 的速率、通道和 CDR 寄存器也没有在 I2C 基础验证阶段改动。

### SFL 和 QSPI Flash

- 自定义 SFL bridge 已在当前卡上完成 SRAM 加载和 Flash 访问验证。
- 已用只读 Examine 读取当前物理卡的完整原始 Flash。
- 原始备份大小为 `134218006` 字节，SHA-256 为 `77537b66db42e28aff0e354b1051f1f08ff20780e214167d4aa101634ec01d14`。
- 原始备份已设为只读，并在第二块物理磁盘保存副本。
- `pcie_temp_demo-MT25QU01G.jic` 已完成 Program/Verify，Quartus 报告 0 errors、0 warnings。
- 已写入 JIC 的 SHA-256 为 `7dfe7ecfdfd9749d2dfd87dc1d25d62af24cf0b5b5bf1d79dd71c2897c9b0cba`。
- 详细记录见 [pcie-temp-demo/FLASH_BACKUP_BOARD2.md](pcie-temp-demo/FLASH_BACKUP_BOARD2.md)。

后续板级验证默认只写 FPGA SRAM，不改 Flash。只有明确需要持久化并重新执行备份、回滚和冷启动检查时，才考虑新的 Flash 写入。

### 第一组 FPGA PCIe x8 和温度读取

- Flash 冷启动后，主机能枚举 FPGA 端点 `1172:e003`。
- BAR0 为 64 字节寄存器区，BAR2 为 8 KiB 测试 RAM。
- BAR0 设计 ID 返回 `0x43505433`（`CPT3`）。
- 100 MHz heartbeat 连续变化，证明用户逻辑正在运行。
- Arria 10 内置温度传感器可通过 BAR0 读取；一次已记录的空闲温度为 `50.37 C`。
- 当前 ABI 见 [pcie-temp-demo/REGISTERS.md](pcie-temp-demo/REGISTERS.md)。

该工程属于**功能已验证**，还不是完整的时序签核版本。现有 `build.log` 记录完整编译 0 errors、110 warnings，Timing Analyzer 明确提示设计未对 setup/hold 完全约束。后续复用 PCIe 基础设施时需要整理未约束路径和 warning，不能把当前结果当作生产级闭合结论。

## 准备验证

新工程计划放入独立的 `board-validation/` 目录，各子项目保留源文件、约束和验证记录，不提交 `db/`、`incremental_db/`、日志或大型编程文件。

### 1. 两组 DDR4

计划分别建立 `board-validation/ddr4-top/` 和 `board-validation/ddr4-bottom/`，最后再考虑双通道工程：

- 使用社区已验证的 72-bit 引脚和现有 EMIF 参数作为依据，在 Quartus 22.1 中重新生成 IP。
- 先单独验证每组 EMIF 的 PLL lock、local calibration success/fail 和 EMIF Toolkit 可见性。
- 校准通过后运行地址线、数据线、walking-bit、固定模式、伪随机模式和大范围读写测试。
- 分别记录 64-bit 数据和 8-bit ECC/附加字节通道的结果，避免只测试低位数据。
- 单通道通过后再做双通道并行压力测试，并持续读取 FPGA 温度。

验收条件：两组 EMIF 分别校准成功；可用地址范围和容量有本地证据；长时间内存测试错误计数为 0；对应时钟和 EMIF 时序报告完成检查。

### 2. QSFP+、retimer 和高速收发器

计划建立 `board-validation/qsfp-superlite/`：

- 先通过 I2C 验证 QSFP presence、EEPROM 和 `DS250DF810` 管理面。
- 确认模块、电缆和散热条件后，再解除高速 TX reset/mute。
- 以每 lane `10.3125 Gbit/s` 为第一目标；retimer 社区配置为广播通道后设置相应速率。
- 先验证 TX PLL lock、RX CDR lock、lane lock、deskew、PRBS/error counter 和温度。
- 如果有合适的 QSFP 环回头或另一端设备，再验证完整的 4-lane 外部路径。
- SuperLite II 是链路测试协议，不等同于 Ethernet、InfiniBand 或 FPGA 到 ConnectX-4 的通信。

验收条件分两级：管理面和内部收发器状态可以单卡完成；QSFP cage 的完整外部收发路径必须有环回头、线缆加第二端或合适的网络设备。

## 暂时不好验证

| 项目 | 当前原因 | 解锁条件 |
| --- | --- | --- |
| 第二组 FPGA PCIe Gen3 x8 | 不确定主板是否启用了对应 bifurcation/lane；用户要求暂不验证 | 确认主板插槽拓扑和 BIOS bifurcation 后再做 |
| ConnectX-4 Lx 独立 PCIe | 标准 PCIe 卡版本上该接口走独立连接，当前主机未枚举 `15b3:*` 设备 | 确认 OCuLink/主板连接并能枚举 NIC |
| FPGA 与 ConnectX-4 板内高速连接 | 社区仍标记为未验证，可能还涉及未识别控制信号、U22/U55 和 CX4 端口配置 | 先完成 I2C/GPIO 映射及 CX4 管理面，再上 40G Ethernet 评估 IP |
| QSFP SuperLite 完整端到端 | 单卡不能证明 cage、线缆和远端 RX/TX 全路径 | 准备 QSFP+ 环回头，或第二张卡/兼容网络端点 |
| 50 Gbit/s 完整链路 | 需要 12.5 Gbit/s/lane 参数、匹配的另一端和更高热负载验证 | 40 Gbit/s 稳定通过后再升级 |
| 高速信号眼图、抖动和正式 BER 裕量 | FPGA 状态计数器只能做数字功能判断，不能替代模拟信号完整性测量 | 出现无法解释的 CDR/BER 问题时借用高速示波器或 BERT |
| 外部排针未知信号、U20/U22/U55 未知功能 | 资料不足，猜测性输出可能冲突或损伤器件 | 原理图追线、万用表确认电压域，并先做高阻输入观测 |
| 满载热设计认证 | 当前只有一次约 50.37 C 的空闲温度，不能代表 DDR4/XCVR 满载 | 确保服务器级气流，增加持续负载和多点温度记录 |

普通逻辑分析仪不适合直接观察 10.3125/12.5 Gbit/s 收发器通道。当前阶段优先使用 PLL/CDR/lock 状态、PRBS、错误计数、I2C 状态和温度完成数字诊断；只有数字配置已确认而链路仍异常时，才考虑高速示波器或误码仪。

## 验证顺序和安全边界

1. 每次实验前检查 JTAG ID、USB 状态、气流和当前温度。
2. 所有工程使用 Quartus 22.1 和 `10AXF40AA` 从源文件重新编译。
3. 先完成 LED、时钟和输入采样，再扫描 I2C。
4. DDR4 两个通道分别验证，避免同时引入两个高风险接口。
5. QSFP 先管理面、再低风险内部状态，最后才启用外部高速发送。
6. 新设计先写 SRAM；写入前不保留 PCIe BAR `mmap`，写入后重新检查 JTAG。
7. 每个构建记录错误、critical warning、时序结果、SOF SHA-256、JTAG ID、温度和硬件现象。
8. 第二组 PCIe x8 不实例化、不训练；未知或未使用引脚保持输入/三态。
9. 除非用户再次明确要求并完成备份/回滚检查，否则不改 QSPI Flash。
