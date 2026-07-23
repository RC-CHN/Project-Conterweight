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
| 当前 SRAM 设计 | `board-validation/ddr4-2133` 的双通道 DDR4-2133 验证镜像，BIST 已停止（断电后仍回到 Flash 设计） |
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

基础 I2C 扫描没有发现常见地址 `0x50` 的 QSFP EEPROM。后续专用 QSFP 管理镜像已确认这是因为当前没有安装模块/线缆，而不是仅凭 NACK 猜测；见下一节。

### QSFP 管理面、retimer 配置和 FPGA 内部高速回环

- `board-validation/qsfp-superlite` 的管理镜像只连接 U59、Y5、`MODPRSL` 和 I2C channel 1，不实例化 transceiver，也不驱动 QSFP 高速 TX lane。
- Quartus 22.1 完整编译 0 errors、9 warnings；setup/hold 完全约束且所有 TNS 为 0。最差 setup 为 `+0.624 ns`，最差 hold 为 `+0.016 ns`。
- SOF SHA-256 为 `c78b7beb8e9e6f42aa7e779e7a745e4b700461283a3789998e7d628f95d89338`；SRAM 配置 0 errors、0 warnings，配置后 JTAG 仍识别 `0x02E060DD`。
- `MODPRSL=1` 明确报告当前没有 QSFP 模块/线缆；`0x50` 同时 NACK，因此 EEPROM 字段属于未具备测试条件，不标失败。
- 三次 Y5 测量约为 `644.528 MHz`，与标称 644.53125 MHz 一致。
- DS250DF810 在 `0x22` 稳定 ACK；配置前读到 `0xff=0x21`、`0x2f=0x54`。
- 在“模块不存在”的脚本门禁下，已执行社区明确记录的易失性广播速率序列：写 `0xff=0x03`，再保留 `0x2f` 低半字节并将高半字节清零；写后及独立复查均为 `0xff=0x03`、`0x2f=0x04`，对应 10.3125 Gbit/s quick-rate 选择。
- 所有事务前后 SCL/SDA 都为空闲高，FPGA OE 均为 0；QSPI Flash 未触碰。
- 四通道内部回环镜像使用 Y5 驱动 transceiver-mode fPLL；5.15625 GHz MCGB 时钟驱动四条 non-bonded TX lane，每条物理线速率为 `10.3125 Gbit/s`，四路 RX CDR 直接使用 Y5。
- Quartus 22.1 对内部回环镜像完整编译为 0 errors、9 warnings，Fitter 选择 `10AXF40AA`；setup/hold 完全约束，零未约束时钟/端口/输入输出路径，所有 timing corner 的 setup、hold、recovery、removal 和 pulse-width slack 均为正。
- 内部回环 SOF SHA-256 为 `5e2e58ded09831fc50b92d9e9822e1652cb0bdefabdd498e7aaec554729b966e`；仅写入 SRAM，Programmer 0 errors、0 warnings，配置前后 JTAG 均识别 `0x02E060DD`。
- 新镜像配置后、任何控制写入前的只读检查确认 `source=0x00`、`safe_enable=0`，证明硬件上电默认状态不会启用高速发送路径。
- fPLL lock、四路 TX/RX ready、四路 CDR lock-to-data/ref、四路 PCS block lock 和 checker 均通过，TX/RX calibration busy、FIFO full/partial-full/overflow 均为 0。
- lane 0..3 的独立注错逐条通过；清零后 60 秒 soak 每路处理约 93.86 亿个 66-bit block，四路 error count 和 lock-loss count 均保持 0，结束温度为 `52.40 C`。
- 测试清理路径最终确认 `source=0x00`、`safe_enable=0`；当前 SRAM 高速路径关闭，QSPI Flash 未触碰。
- 完整证据和 warning 审核见 [board-validation/qsfp-superlite/RESULTS.md](board-validation/qsfp-superlite/RESULTS.md)。

这两步证明了参考时钟、presence 输入、管理 I2C、retimer 寄存器访问、已知的速率快速配置序列，以及 FPGA 内部四路 TX PCS/PMA、串行回环、RX PMA/CDR/PCS 数字路径。内部串行回环不经过 retimer、cage、模块或线缆，因此仍没有证明外部高速通路。

### 两组 DDR4

- `board-validation/ddr4-dual` 同时实例化了两套相互独立的 72-bit EMIF（64-bit 数据 + 8-bit ECC），使用 DDR4-1600 参数：800 MHz 存储器时钟、200 MHz quarter-rate 用户时钟和两路 266.667 MHz 板载参考时钟。
- 工程已加入两套独立的片上 512-bit 全地址 BIST，并用 Quartus 22.1 对 `10AXF40AA` 完整编译，0 errors、31 warnings；最终 SOF SHA-256 为 `9725aef1202a5e6fc51d66ba13d1fea73e870550153e35e3b7ebdfac48853a38`。
- 四个时序角的 setup、hold、recovery、removal 和 minimum pulse-width slack 均为正且 TNS 为 0；最差 setup 为 `+0.423 ns`，最差 hold 为 `+0.013 ns`，最差 recovery 为 `+0.266 ns`，最差 removal 为 `+0.174 ns`，最差 pulse-width 为 `+0.300 ns`。
- 最终 SOF 已写入 SRAM，Quartus Programmer 报告 0 errors、0 warnings；配置前后 JTAG 均稳定识别 `0x02E060DD`。
- 两个控制器均报告 `pll_locked=1`、`cal_success=1`、`cal_fail=0`，各自的 200 MHz 用户域 heartbeat 持续变化。
- 两路 BIST 同时运行，在 `27.345` 秒内各完成一轮；每路遍历 `0x00000000` 至 `0x7fffffc0` 的全部 33,554,432 条 64-byte 地址行，覆盖完整 2 GiB 控制器用户地址空间。
- 每路依次完成两种 LFSR、旋转 one-hot 和旋转 one-cold 共 4 种全宽写入/读回/比较模式，合计每路 16 GiB 流量；两路 error count、byte-error mask 和 ECC interrupt 全为 0。
- 两个独立的 2 GiB Avalon 窗口都在 `0x00000000` 至 `0x7fffffc0` 间抽样了 7 个分散地址；每处完成一条 64-byte 数据的写入、读回和比较，两边全部通过，ECC interrupt 始终为 0。
- 详细的构建、warning 审核、时序例外边界、System Console 测试和限制见 [board-validation/ddr4-dual/RESULTS.md](board-validation/ddr4-dual/RESULTS.md)。

在 1600 MT/s 基线上，又完成了独立的 DDR4-2133 提频验证：

- `board-validation/ddr4-2133` 从已验证的 1600 配置可重复生成，两套 EMIF 都改为 1066.667 MHz 存储器时钟和约 266.7 MHz quarter-rate 用户时钟；两条 JTAG-to-DDR 数据路径从该变体移除。
- 最终完整编译 0 errors、29 warnings，Fitter 选择 `10AXF40AA`；多角 setup/hold 完全约束且所有 TNS 为 0，最差 setup/hold/recovery/removal/pulse-width 分别为 `+0.269`/`+0.013`/`+0.574`/`+0.151`/`+0.143 ns`。
- 最终 SOF 大小为 `36,857,644` 字节，SHA-256 为 `08206bc38b482294a7aed5dacfa2577d16cf9f04ae7ebcb9c6c41c6ce2a1c79c`；仅写入 SRAM，Programmer 0 errors、0 warnings。
- 两个控制器均再次报告 PLL locked、calibration success、无 calibration failure、无 ECC interrupt；默认 `bist_control=0`，配置后不会自行覆盖内存。
- 最终双通道并发测试在 `36.284` 秒内每路完成 2 轮全地址/4 图样 BIST，即每通道 32 GiB、总计 64 GiB 写读流量；两路 error count、first-error address 和 byte-error mask 全为 0。
- 测试前温度 `59.84 C`，结束温度 `61.20 C`；测试后两路引擎均停止，JTAG 仍稳定识别 `0x02E060DD`，QSPI Flash 未触碰。
- 构建、warning 边界、两周期 reset recovery 约束和完整实测记录见 [board-validation/ddr4-2133/RESULTS.md](board-validation/ddr4-2133/RESULTS.md)。

当前结论是两套控制器配置的完整 2 GiB/通道、共 4 GiB 用户数据已经在 DDR4-1600 和 DDR4-2133 两档完成本地全地址并发验证。这里的 2 GiB 不是缩窄的 JTAG 调试窗口，而是当前 25-bit word-address × 64-byte 数据宽度所能覆盖的完整控制器地址范围。该结果仍不能替代对社区所称 5 GB fitted / 约 4.5 GB usable 组织的颗粒与几何审计，也不是峰值带宽、长时间保持或满载热认证。

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

### 1. DDR4 峰值带宽、长期热稳定和几何审计

双控制器 2 GiB/通道的全地址并发 BIST 已经在 DDR4-1600 和 DDR4-2133 两档通过，下一步计划在现有工程基础上增加：

- 支持多 outstanding/流水访问和吞吐量计数的 traffic generator，测量双通道最大可持续带宽。
- 加入温度遥测，在服务器级气流下进行数小时并发耐久与保持测试。
- 核对板上颗粒和控制器几何，解释社区 5 GB fitted / 约 4.5 GB usable 与当前已验证 4 GiB 用户数据之间的差异。

验收条件：目标速率下完整时序闭合并校准成功；双通道长期并发错误计数为 0；持续负载下温度、供电和吞吐量稳定。

### 2. QSFP+、retimer 和高速收发器

`board-validation/qsfp-superlite/` 的管理面和 FPGA 内部高速回环均已完成；下一阶段需要外部端点：

- 当前无模块，QSFP EEPROM 需安装兼容模块或 DAC 后再验证。
- 如果有合适的 QSFP 环回头或另一端设备，再验证完整的 4-lane 外部路径。
- 外部测试需继续使用逐 lane error/lock-loss counter，并增加足够长的 BER soak；多 lane 协议对齐/deskew 只能在实际外部协议或 SuperLite 对端上验证，不能由四条相互独立的内部回环代替。
- SuperLite II 是链路测试协议，不等同于 Ethernet、InfiniBand 或 FPGA 到 ConnectX-4 的通信。

验收条件分三级：管理面和 FPGA 内部收发器已单卡通过；QSFP cage 的完整外部收发路径必须有环回头、线缆加第二端或合适的网络设备；协议互通还要使用对应 Ethernet、InfiniBand 或 SuperLite 端点单独验收。

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
| 满载热设计认证 | 已有 QSFP 60 秒和 DDR4-2133 36 秒短负载温度记录，最高约 61.20 C，但不能代表数小时持续满载 | 确保服务器级气流，增加持续负载和多点温度记录 |

普通逻辑分析仪不适合直接观察 10.3125/12.5 Gbit/s 收发器通道。当前阶段优先使用 PLL/CDR/lock 状态、PRBS、错误计数、I2C 状态和温度完成数字诊断；只有数字配置已确认而链路仍异常时，才考虑高速示波器或误码仪。

## 验证顺序和安全边界

1. 每次实验前检查 JTAG ID、USB 状态、气流和当前温度。
2. 所有工程使用 Quartus 22.1 和 `10AXF40AA` 从源文件重新编译。
3. 先完成 LED、时钟和输入采样，再扫描 I2C。
4. DDR4 双控制器 2 GiB/通道的全地址并发 BIST 已在 1600/2133 MT/s 通过；后续做峰值带宽、长时间压力、温度遥测和颗粒/几何审计。
5. QSFP 管理面和低风险内部回环已通过；下一步只有具备合适端点时才验证外部高速路径。
6. 新设计先写 SRAM；写入前不保留 PCIe BAR `mmap`，写入后重新检查 JTAG。
7. 每个构建记录错误、critical warning、时序结果、SOF SHA-256、JTAG ID、温度和硬件现象。
8. 第二组 PCIe x8 不实例化、不训练；未知或未使用引脚保持输入/三态。
9. 除非用户再次明确要求并完成备份/回滚检查，否则不改 QSPI Flash。
