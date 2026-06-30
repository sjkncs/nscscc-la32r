# LynxCore 优化路线图 - 基于历届获奖作品分析

## 一、评分标准（从竞赛章程和参赛经验提取）

龙芯杯个人赛评分主要由以下部分构成：

1. **功能正确性** — 通过全部46条指令测试（基础分，必须满分）
2. **性能测试** — 运行benchmark程序，按执行时间/周期数评分
   - 性能 = IPC × 时钟频率
   - IPC 受 Cache命中率、分支预测准确率、流水线冒险停顿 影响
   - 时钟频率 受 关键路径长度 影响
3. **决赛编程** — 在自己的CPU上运行编写的汇编程序
4. **设计文档** — CPU设计报告质量

**核心公式: 总性能 = IPC × Fmax**

---

## 二、获奖作品架构对比

| 特性         | LynxCore (当前)          | 贾又维 (一等奖)                         | 缪泽晔 (三等奖)                         | 陈圣峰 (二等奖)          |
| ------------ | ------------------------ | --------------------------------------- | --------------------------------------- | ------------------------ |
| 发射宽度     | 单发射                   | **双发射**                        | 单发射                                  | 单发射                   |
| ICache       | 32-entry DM, 1-word line | 32-entry DM, 2-word line,**BRAM** | 64-entry**2-way SA**, 4-word line | 32-entry DM, 1-word line |
| DCache       | **无**             | **有**                            | **有**                            | 无(直接访存)             |
| BPU          | 16-entry BTB, 2-bit      | 8-entry**2-bank** BTB             | **256-entry**, 地址折叠hash       | **无**             |
| 指令缓冲     | 无                       | **4-entry FIFO + 预译码**         | 无                                      | 无                       |
| Cache行大小  | 1 word                   | 2 words (64-bit)                        | **4 words (128-bit)**             | 1 word                   |
| 除法器       | 组合逻辑                 | 多周期(ALU suspend)                     | **多周期不恢复余数**              | 未知                     |
| 分支判定阶段 | EX                       | **MEM**                           | EX                                      | 无BPU                    |
| 时钟频率     | 待测                     | 未知                                    | **160MHz**                        | **250MHz**         |
| 关键优化     | BPU+ICache               | 双发射+指令缓冲+DCache                  | 大BPU+2路ICache+DCache+除法器           | **极致提频**       |

---

## 三、关键发现

### 1. 陈圣峰(二等奖)的启示: 提频 > 复杂微架构

- 没有BPU，没有DCache，只有最简单的ICache
- 但时钟频率推到了 **250MHz**（其他选手约100-160MHz）
- 说明: **时钟频率对总性能的贡献被严重低估**
- 简单设计 + 高频率 可以击败复杂设计 + 低频率

### 2. 贾又维(一等奖)的核心优势: 双发射

- **双发射是IPC翻倍的关键**（理论IPC从1.0提升到接近2.0）
- 配套设施: 4-read/2-write RF, 双ALU, 双data_forward, 指令缓冲
- 复杂度极高，但性能回报巨大

### 3. 缪泽晔(三等奖)的均衡路线

- 与LynxCore架构最接近（单发射5级流水线）
- 核心差异: 256-entry BPU + 2-way ICache + DCache + 多周期除法器
- 时钟频率 160MHz（说明单发射可以推到较高频率）

---

## 四、LynxCore 优先级优化路线图

### Phase 0: 功能验证 ✅ 已完成

- [X] 禁用BPU/ICache进行基线功能验证准备

### Phase 0.5: 多周期除法器 ✅ 已完成

- [X] 实现非恢复余数除法器 (divider.v), 34周期延迟
- [X] ALU移除组合除法逻辑，改用divider结果
- [X] EX_stage集成divider，生成div_suspend/div_done
- [X] myCPU流水线控制集成div_suspend/div_done

### Phase 1: ICache 4-word cache lines ✅ 已完成

- [X] CACHE_BLK_LEN=4, 128-bit cache lines
- [X] ICache重写: Tag=addr[31:9], Index=addr[8:4], WOff=addr[3:2]
- [X] Refill收集4个word后整行写入cache

### Phase 2: DCache实现 ✅ 已完成

- [X] 32-entry直接映射, 4-word (128-bit) cache lines
- [X] 写穿透+写绕过策略 (stores bypass cache, 命中时invalidate)
- [X] 外设地址(0xBFAF_xxxx)自动bypass，不缓存，单字读
- [X] rf_is_cacheable标志控制refill_done阈值

### Phase 3: BPU扩大 + 地址折叠 ✅ 已完成

- [X] BTB从16扩大到256 entries
- [X] 地址折叠XOR hash: index = PC[9:2] ^ PC[17:10]
- [X] Tag = PC[31:10] (22 bits)

### Phase 4: ICache升级2路组相联 ✅ 已完成

- [X] 2-way × 32 sets = 64 entries (容量翻倍)
- [X] 1-bit pseudo-LRU替换策略
- [X] 同时检查两路hit，mux选择命中行数据

### Phase 5: 时钟频率优化 [进行中]

- [ ] Vivado综合验证功能正确性
- [ ] 检查关键路径（Vivado Timing Report）
- [ ] 优化组合逻辑链: ALU结果→前递→ID阶段
- [ ] 考虑寄存器retiming
- [ ] 目标: 150MHz+

### Phase 6: 双发射 [低优先级, 高回报但极高风险]

- 需要: 双ALU, 4R2W寄存器堆, 双data_forward, 双pipeline
- 改动量: 接近重写整个CPU
- 仅在上述优化全部完成且时间充裕时考虑

---

## 五、各阶段预期收益估算

| 优化阶段                    | 对IPC影响         | 对Fmax影响         | 实现难度   | 综合性价比           |
| --------------------------- | ----------------- | ------------------ | ---------- | -------------------- |
| Phase 1: 多周期除法器       | 略降(除法变慢)    | **+50-100%** | ★★☆☆☆ | **★★★★★** |
| Phase 2: ICache 4-word line | **+15-30%** | 无                 | ★★☆☆☆ | **★★★★★** |
| Phase 3: DCache             | **+20-40%** | 无                 | ★★★☆☆ | **★★★★☆** |
| Phase 4: BPU扩大            | **+5-10%**  | 无                 | ★★☆☆☆ | **★★★☆☆** |
| Phase 5: 2-way ICache       | **+5-10%**  | 无                 | ★★★☆☆ | **★★★☆☆** |
| Phase 6: 提频优化           | 无                | **+20-50%**  | ★★★☆☆ | **★★★★☆** |
| Phase 7: 双发射             | **+50-80%** | 可能降低           | ★★★★★ | ★★☆☆☆           |
