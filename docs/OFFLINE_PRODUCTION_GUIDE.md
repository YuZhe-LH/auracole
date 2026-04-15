# OFFLINE_PRODUCTION_GUIDE

## 文档目的

这份文档说明 `res://scripts/industry_map/` 下这套离线工业生产线系统的设计思路、代码职责、接入步骤、限制条件，以及一套可以直接照着做的完整使用示例。

如果你现在最关心的是“我到底该怎么用”，建议按下面顺序阅读：

1. `快速理解整体流程`
2. `完整使用示例：铁锭 -> 铁板`
3. `快速接入指南`
4. `测试场景使用说明`

## 文件结构

这套系统目前由以下几个核心文件组成：

- [ProductionData.cs](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/data/ProductionData.cs)
  - 定义物品、配方、机器快照、推演结果、序列化辅助工具
- [OfflineSimulationEngine.cs](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/engine/OfflineSimulationEngine.cs)
  - 负责纯逻辑的离线事件驱动推演
- [MachineController.cs](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/runtime/MachineController.cs)
  - 负责单台机器在 Godot 场景中的运行时状态
- [ProductionLineManager.cs](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/runtime/ProductionLineManager.cs)
  - 负责场景初始化、快照保存、离线恢复、结果回写、UI 刷新
- [test_offline_production.tscn](/C:/Users/daxingyi/Documents/auracole/scenes/test_offline_production.tscn)
  - 已经搭好的测试场景

## 快速理解整体流程

你可以把这套系统理解成四个步骤：

1. 玩家下线时，把所有机器状态保存成快照
2. 玩家上线时，计算“离线了多少秒”
3. 用离线秒数和快照交给 `OfflineSimulationEngine`
4. 引擎直接跳事件，不逐秒 Tick，最后把结果写回场景

对应流程图如下：

```text
场景中的 MachineController / ProductionLineManager
        ↓
SaveSnapshot()
        ↓
user://production_snapshot.json
        ↓
LoadAndSimulateOffline()
        ↓
计算离线秒数 Δt
        ↓
OfflineSimulationEngine.SimulateOffline()
        ↓
事件驱动时间跳跃
        ↓
得到最终 MachineSnapshot[] + TotalProduced
        ↓
ApplyResultToScene()
        ↓
更新 UI、机器状态、日志
```

## 架构原理

### 1. 数据层做什么

`ProductionData.cs` 提供的是“可保存、可计算、可还原”的基础结构：

- `Item`
  - 定义物品 ID、名称、堆叠上限
- `Recipe`
  - 定义配方 ID、周期时间、输入输出
- `MachineSnapshot`
  - 表示单台机器在某个时刻的完整状态
- `ProductionSnapshotFile`
  - 表示整个生产线的顶层存档
- `SimulationResult`
  - 表示一次离线推演的返回值

这些对象本身不依赖 Godot 场景树，可以单独拿去做纯逻辑测试。

### 2. 引擎层做什么

`OfflineSimulationEngine.cs` 只负责一件事：

- 输入：离线开始时的快照数组 + 离线秒数
- 输出：离线结束时的快照数组 + 累计产出

它不关心：

- UI 长什么样
- 节点摆在哪里
- 玩家是不是点了按钮

它只关心机器之间怎么消耗输入、推进进度、产生产出、遇到背压后怎么停。

### 3. 运行时层做什么

`ProductionLineManager.cs` 和 `MachineController.cs` 负责把引擎接到 Godot 场景里：

- `MachineController`
  - 保存单机输入缓存、输出缓存、待输出缓存、当前配方、当前状态
- `ProductionLineManager`
  - 收集场景里所有机器
  - 保存快照
  - 读取快照
  - 算离线时间
  - 调用引擎
  - 把结果写回机器节点
  - 刷新状态栏和日志

## 事件驱动时间跳跃是怎么工作的

### 为什么不用 `while(dt--) tick()`

如果你离线 24 小时，再用一秒一次的 Tick 去补算，那么一台机器至少要跑 86400 次循环，多台机器会更重。更麻烦的是，这种方式很容易引入：

- 帧率误差
- 浮点累积误差
- 因执行顺序不同而出现的非确定性

所以这里不用后台 Tick，而是只在“真正发生变化的时刻”推进时间。

### 当前版本会处理哪些事件

当前代码按批处理工业模型来做，主要关注这些事件：

- `加工完成`
- `输入不足导致无法开工`
- `输出写不进去导致背压`
- `下游腾出空间后重新尝试写出`

### 一次循环里发生什么

对于每台正在运行的机器，引擎会计算它距离下一个变化点还剩多少秒：

- `timeToComplete`
- `timeToInputDeplete`
- `timeToOutputFull`

然后：

1. 取全局最小时间 `nextEventDt`
2. 逻辑时钟直接前进 `nextEventDt`
3. 只处理这个时间点发生变化的机器
4. 如果某些机器因为下游被唤醒，再放进即时队列继续处理
5. 循环到离线时间结束或系统进入稳态

### 当前实现的批处理语义

当前实现不是“连续流量”模型，而是“批量生产”模型：

- 开工瞬间一次性扣除输入
- 完工瞬间一次性生成输出
- 如果输出塞不下，先尝试送下游
- 还塞不下就进 `PendingOutputBuffer`

这意味着：

- 输入不是一边加工一边慢慢扣
- 输出也不是一边加工一边慢慢堆

这么做的好处是：

- 逻辑简单
- 结果稳定
- 更容易保证离线推演的确定性

## 为什么这个方案更适合离线工业系统

### 算力成本更低

事件跳跃模型只在状态变化点计算，不按秒重放离线过程，因此更接近：

- `O(N log N + E)`

其中：

- `N` 是机器数量
- `E` 是依赖边或路由边数量

### 更容易做反作弊

核心引擎不依赖：

- `Time.GetTicksMsec()`
- 帧时间
- 实时物理推进

所以如果你以后要接服务端时间戳，只要把 `ProductionLineManager` 中计算 `Δt` 的逻辑替换掉即可。

### 更容易识别稳态

所谓稳态，就是：

- 没有机器还能开工
- 没有机器还能完工
- 没有待输出能继续写出去

这时继续模拟也不会变化，可以提前结束，不浪费计算。

## 核心数据结构说明

### MachineState

`MachineState` 目前有四种状态：

- `Idle`
  - 当前空闲，可能没有输入，也可能配置还没完成
- `Processing`
  - 正在加工
- `InputBlocked`
  - 因输入不足无法继续
- `OutputBlocked`
  - 因输出背压无法继续

### MachineSnapshot

`MachineSnapshot` 是离线系统最重要的数据结构之一。字段意义如下：

- `MachineId`
  - 机器唯一标识，用来和场景里的 `MachineController` 对应
- `DisplayName`
  - 机器显示名称
- `Recipe`
  - 当前机器使用的配方
- `State`
  - 当前离散状态
- `ProgressSeconds`
  - 当前周期已推进的秒数
- `AutoStart`
  - 输入满足时是否自动开工
- `InputBuffer`
  - 输入缓存区
- `OutputBuffer`
  - 输出缓存区
- `PendingOutputBuffer`
  - 因背压未能写完的结果
- `InputCapacity`
  - 输入容量限制
- `OutputCapacity`
  - 输出容量限制
- `OutputRoutes`
  - 下游输出路由
- `SortOrder`
  - 用于稳定处理顺序

### SimulationResult

`SimulationResult` 返回以下关键信息：

- `FinalSnapshots`
  - 离线结束后每台机器的最终状态
- `TotalProduced`
  - 离线期间累计产出
- `SimulatedSeconds`
  - 实际参与推演的秒数
- `ProcessedTimedEvents`
  - 处理过多少定时事件
- `ReachedSteadyState`
  - 是否提前进入稳态

## 快照文件格式示例

快照会保存到：

- `user://production_snapshot.json`

一个简化后的 JSON 示例如下：

```json
{
  "logout_unix_time": 1765020000,
  "machines": [
    {
      "machine_id": "machine_01",
      "display_name": "基础冶炼机",
      "recipe": {
        "id": "smelt_iron_plate",
        "cycle_time": 5.0,
        "inputs": {
          "iron_ingot": 2
        },
        "outputs": {
          "iron_plate": 1
        }
      },
      "state": "Idle",
      "progress_seconds": 0.0,
      "auto_start": true,
      "input_buffer": {
        "iron_ingot": 10
      },
      "output_buffer": {},
      "pending_output_buffer": {},
      "input_capacity": {
        "iron_ingot": 100
      },
      "output_capacity": {
        "iron_plate": 100
      },
      "output_routes": [],
      "sort_order": 0
    }
  ]
}
```

这个结构是扁平的，目的是方便：

- 直接读 JSON 排查问题
- 热更新字段
- 后续迁移到服务端

## 完整使用示例：铁锭 -> 铁板

这一节是最重要的。如果你想知道“这些代码该怎么用”，直接照这个例子做。

### 需求

我们要做一台最简单的机器：

- 输入：`iron_ingot x2`
- 周期：`5 秒`
- 输出：`iron_plate x1`

玩家下线前给它 10 个铁锭。离线恢复时，系统应该算出它最多能生产 5 个铁板。

### 第 1 步：在场景里放一个管理器

建立一个 `Control` 根节点，挂载：

- [ProductionLineManager.cs](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/runtime/ProductionLineManager.cs)

如果你不想自己搭，可以直接打开：

- [test_offline_production.tscn](/C:/Users/daxingyi/Documents/auracole/scenes/test_offline_production.tscn)

这个测试场景已经帮你把 UI 和管理器都接好了。

### 第 2 步：在场景里放一台机器

在管理器根节点下添加一个 `Node2D`，挂载：

- [MachineController.cs](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/runtime/MachineController.cs)

然后在 Inspector 中设置：

- `MachineId = machine_01`
- `DisplayName = 基础冶炼机`
- `RecipeId = smelt_iron_plate`
- `AutoStart = true`
- `InputCapacity["iron_ingot"] = 100`
- `OutputCapacity["iron_plate"] = 100`

如果这台机器就是你场景里唯一的机器，那它作为管理器的子节点即可，不一定非要手动填 `MachinePaths`。

### 第 3 步：给管理器配置配方

在 `ProductionLineManager` 的 `RecipeJsonById` 中放入一条 JSON：

```json
{
  "id": "smelt_iron_plate",
  "cycle_time": 5.0,
  "inputs": {
    "iron_ingot": 2
  },
  "outputs": {
    "iron_plate": 1
  }
}
```

当前测试场景如果没有手动配置，`ProductionLineManager` 会自动补一条同样的默认配方。

### 第 4 步：给第一台机器灌初始库存

`ProductionLineManager` 会在 `_Ready()` 阶段调用 `ApplyInitialRecipesAndInventory()`，把 `InitialInventory` 中的物品送到第一台机器。

例如设置：

```text
InitialInventory["iron_ingot"] = 10
```

这样游戏启动后，第一台机器就会有 10 个铁锭作为输入缓存。

### 第 5 步：保存离线快照

当玩家下线时，调用：

```csharp
SaveSnapshot();
```

它会把当前机器状态写到：

```text
user://production_snapshot.json
```

### 第 6 步：玩家上线时恢复离线结果

当玩家重新上线时，调用：

```csharp
LoadAndSimulateOffline();
```

或者在测试场景里直接点击：

```text
模拟离线 24 小时
```

如果你想强制指定离线时间做测试，也可以直接调用：

```csharp
LoadAndSimulateOffline(86400.0f);
```

### 第 7 步：这次离线会发生什么

假设玩家下线时机器状态如下：

- 输入：`iron_ingot x10`
- 输出：空
- 状态：`Idle`
- 进度：`0`

那么离线恢复时，引擎会这样算：

1. 检查是否满足开工条件
   - 需要 `iron_ingot x2`
   - 当前有 `iron_ingot x10`
   - 可以开工
2. 开工瞬间扣掉 `iron_ingot x2`
   - 剩余 `iron_ingot x8`
3. 登记下一事件
   - `5 秒后完工`
4. 时间直接跳到 5 秒
5. 产出 `iron_plate x1`
6. 继续重复以上过程

总共能做几轮：

- 10 个铁锭
- 每轮消耗 2 个
- 所以总共 5 轮

最后结果：

- 输入：`0`
- 输出：`iron_plate x5`
- 状态：`InputBlocked`

因为原料已经没了，机器无法继续开工。

### 第 8 步：你在界面上会看到什么

如果使用测试场景，你应该看到：

- `输入库存: 0`
- `输出库存: iron_plate x5`
- `机器状态: InputBlocked`
- `离线时长: 86400s`

底部日志类似：

```text
离线推演完成：86400 秒，事件数 5，累计产出 iron_plate x5
```

## 多机器流水线示例：冶炼机 -> 装配机

上一个例子只用了单机。下面这个例子说明如何把多台机器连成一条真正的流水线。

### 目标

我们现在做两台机器：

- `Smelter`
  - 输入：`iron_ingot x2`
  - 输出：`iron_plate x1`
  - 周期：`5 秒`
- `Assembler`
  - 输入：`iron_plate x2`
  - 输出：`gear x1`
  - 周期：`4 秒`

流水线目标是：

- 玩家先把铁锭送进 `Smelter`
- `Smelter` 做出铁板后，不是留在自己输出口，而是自动送到 `Assembler`
- `Assembler` 收到足够铁板后开始生产齿轮

也就是说，这条线的流向是：

```text
iron_ingot
   ↓
Smelter
   ↓ iron_plate
Assembler
   ↓ gear
最终输出
```

### 第 1 步：在场景里放两台 MachineController

假设你的场景结构像这样：

```text
ProductionLineManager
├── Smelter
└── Assembler
```

其中：

- `Smelter` 挂 [MachineController.cs](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/runtime/MachineController.cs)
- `Assembler` 也挂 [MachineController.cs](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/runtime/MachineController.cs)

在 Inspector 中分别配置：

#### Smelter

- `MachineId = smelter_01`
- `DisplayName = 冶炼机`
- `RecipeId = smelt_iron_plate`
- `AutoStart = true`
- `InputCapacity["iron_ingot"] = 100`
- `OutputCapacity["iron_plate"] = 100`

#### Assembler

- `MachineId = assembler_01`
- `DisplayName = 装配机`
- `RecipeId = assemble_gear`
- `AutoStart = true`
- `InputCapacity["iron_plate"] = 100`
- `OutputCapacity["gear"] = 100`

### 第 2 步：在 ProductionLineManager 里准备两条配方

你需要在 `RecipeJsonById` 中至少配置两条配方：

```json
{
  "id": "smelt_iron_plate",
  "cycle_time": 5.0,
  "inputs": {
    "iron_ingot": 2
  },
  "outputs": {
    "iron_plate": 1
  }
}
```

```json
{
  "id": "assemble_gear",
  "cycle_time": 4.0,
  "inputs": {
    "iron_plate": 2
  },
  "outputs": {
    "gear": 1
  }
}
```

配置后，`ProductionLineManager` 在启动时会调用 `BuildRecipeCache()`，然后在 `ApplyInitialRecipesAndInventory()` 中把对应配方分给各台机器。

### 第 3 步：把上游机器输出连接到下游机器输入

这是“流水线”成立的关键。

当前代码的连接方式不是拖线 UI，而是通过 `MachineRoute` 描述路由关系。相关定义在：

- [MachineRoute](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/data/ProductionData.cs#L96)
- [MachineSnapshot.OutputRoutes](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/data/ProductionData.cs#L193)
- [MachineController.SetOutputRoutes](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/runtime/MachineController.cs#L156)

你需要在场景初始化时写一段引导代码，把 `Smelter` 的 `iron_plate` 输出路由到 `Assembler`。

示例代码：

```csharp
using Godot;
using Auracole.IndustryMap.Data;
using Auracole.IndustryMap.Runtime;

public partial class PipelineBootstrap : Node
{
	public override void _Ready()
	{
		MachineController smelter = GetNode<MachineController>("ProductionLineManager/Smelter");
		MachineController assembler = GetNode<MachineController>("ProductionLineManager/Assembler");

		smelter.SetOutputRoutes(new[]
		{
			new MachineRoute
			{
				ItemId = "iron_plate",
				TargetMachineId = assembler.MachineId,
				TargetInputItemId = "iron_plate",
				Priority = 0
			}
		});
	}
}
```

这段代码的意思是：

- 当 `Smelter` 产出 `iron_plate` 时
- 优先把这批 `iron_plate` 送到 `assembler_01`
- 并写入对方的 `iron_plate` 输入缓存

### 第 4 步：给整条线投放初始物料

如果你把初始库存配置在 `ProductionLineManager.InitialInventory` 中，例如：

```text
InitialInventory["iron_ingot"] = 10
```

那么默认会把这批物料送到第一台机器，也就是这里的 `Smelter`。

此时上线后的初始情况是：

- `Smelter`
  - 输入：`iron_ingot x10`
  - 输出：空
- `Assembler`
  - 输入：空
  - 输出：空

### 第 5 步：离线推演时这条流水线会怎么跑

假设玩家离线时间非常长，足够让这条线把原料都处理完。

#### 第一阶段：Smelter 生产铁板

`Smelter` 每轮：

- 消耗 `iron_ingot x2`
- `5 秒` 后产出 `iron_plate x1`

总共有 `iron_ingot x10`，所以它可以生产：

- `iron_plate x5`

但注意，这 5 个铁板不会都留在 `Smelter` 的输出口。因为它已经配置了 `OutputRoutes`，引擎会在完工后先尝试路由给 `Assembler`。

#### 第二阶段：Assembler 消耗铁板生产齿轮

`Assembler` 每轮：

- 消耗 `iron_plate x2`
- `4 秒` 后产出 `gear x1`

由于上游总共只能提供 `iron_plate x5`，所以它最多能做：

- `gear x2`

因为：

- 2 个铁板做 1 个齿轮
- 5 个铁板只能支持完整生产 2 轮
- 最后会剩 `iron_plate x1`

### 第 6 步：最终结果应该是什么

如果这条线没有容量限制、也没有别的阻塞，离线结束后结果大致应为：

#### Smelter

- 输入：`0`
- 输出：`0`
- 状态：`InputBlocked`

为什么输出是 `0`：

- 因为它做出来的 `iron_plate` 已经被优先送到 `Assembler`

#### Assembler

- 输入：`iron_plate x1`
- 输出：`gear x2`
- 状态：`InputBlocked`

为什么还剩 `iron_plate x1`：

- 因为齿轮配方每次要 2 个铁板
- 剩下 1 个铁板不足以再开一轮

### 第 7 步：如果你想做三段流水线

三段线就是继续往后加路由。

例如：

```text
Smelter -> Assembler -> Packer
```

可以这样接：

```csharp
smelter.SetOutputRoutes(new[]
{
	new MachineRoute
	{
		ItemId = "iron_plate",
		TargetMachineId = assembler.MachineId,
		TargetInputItemId = "iron_plate",
		Priority = 0
	}
});

assembler.SetOutputRoutes(new[]
{
	new MachineRoute
	{
		ItemId = "gear",
		TargetMachineId = packer.MachineId,
		TargetInputItemId = "gear",
		Priority = 0
	}
});
```

思路完全一样：

- 上游产什么
- 就把什么通过 `MachineRoute` 送给下游

### 第 8 步：做多机器流水线时最容易出错的地方

#### 1. `ItemId` 写错

如果上游产出是 `iron_plate`，路由里却写成了 `iron_plates`，下游永远收不到。

#### 2. `TargetMachineId` 和真实机器不一致

引擎按 `MachineId` 查机器，不按节点名查。节点名叫 `Assembler` 没问题，但 `MachineId` 必须和路由目标完全一致。

#### 3. `TargetInputItemId` 和下游配方不一致

如果下游配方输入是 `iron_plate`，而你把路由目标输入写成 `plate`，数据会送进去，但下游无法识别为可开工输入。

#### 4. 容量太小导致背压

如果：

- 下游 `InputCapacity` 太小
- 或下游长期来不及消耗

那么上游产物就可能写不进去，最终触发 `OutputBlocked`。

#### 5. 没有在场景初始化时重建路由

当前 `ApplySnapshot()` 会恢复缓冲区和状态，但你仍然应该在场景启动时重新调用一次 `SetOutputRoutes()`，确保运行时连接关系已经建好。

## 快速接入指南

## 快速接入指南

### 1. 如何定义新配方

新增一个配方，最简单的方式就是往 `RecipeJsonById` 里塞 JSON 文本。

例如齿轮配方：

```json
{
  "id": "gear_assembly",
  "cycle_time": 3.5,
  "inputs": {
    "iron_plate": 2
  },
  "outputs": {
    "gear": 1
  }
}
```

然后让某台机器的：

```text
RecipeId = gear_assembly
```

就能让它使用这个配方。

### 2. 如何把机器接进管理器

你有两种方式：

#### 方式 A：自动发现

把 `MachineController` 直接放到 `ProductionLineManager` 根节点下面，管理器会在 `_Ready()` 里自动扫描子节点。

适合：

- 小规模原型
- 测试场景

#### 方式 B：手动指定路径

把机器节点路径放到：

```text
MachinePaths
```

适合：

- 节点层级复杂
- 机器不一定是根节点直属子节点

### 3. 如何保存快照

在玩家离线、切换地图、退出游戏之前调用：

```csharp
SaveSnapshot();
```

建议接入点包括：

- 点击退出按钮时
- 切场景前
- 后台自动存档时

### 4. 如何恢复离线结果

当玩家重新进入生产场景时，调用：

```csharp
LoadAndSimulateOffline();
```

推荐时机：

- 场景初始化完成后
- UI 已经准备好之后
- 机器节点都已加入树之后

### 5. 如何刷新你自己的 UI

当前 `ProductionLineManager` 内部会更新测试场景自带的几个 `Label`。如果你有自己的 UI，可以监听信号：

```csharp
ProductionUpdated
```

然后在你自己的界面脚本里重新读取机器状态。

### 6. 如何替换默认推演逻辑

如果你后续工业系统复杂度提升，可以重点扩展这些方法：

- `TryStartProcessing()`
  - 定义什么时候允许开工
- `ResolveCompletion()`
  - 定义完工时如何产出
- `RouteToDownstream()`
  - 定义怎么把产物送到下游
- `ComputeNextEventDt()`
  - 定义下一事件怎么算
- `ProcessImmediateMachine()`
  - 定义被唤醒机器如何重新评估

## 测试场景使用说明

测试场景路径：

- [test_offline_production.tscn](/C:/Users/daxingyi/Documents/auracole/scenes/test_offline_production.tscn)

### 按钮功能

- `模拟离线 24 小时`
  - 调用 `LoadAndSimulateOffline(86400f)`
  - 如果存在快照文件，就从快照起算
  - 如果不存在快照文件，就拿当前场景状态直接推演
- `手动进料: 铁锭×10`
  - 给第一台机器增加 `iron_ingot x10`
- `保存快照并退出`
  - 保存 `user://production_snapshot.json`
  - 然后退出运行场景

### 顶部状态栏含义

- `输入库存`
  - 显示第一台机器当前输入缓冲区
- `输出库存`
  - 显示第一台机器当前输出缓冲区
- `机器状态`
  - 显示第一台机器当前状态
- `离线时长`
  - 显示最近一次推演使用的秒数

### 推荐测试顺序

1. 打开测试场景
2. 点击 `手动进料: 铁锭×10`
3. 点击 `保存快照并退出`
4. 重新运行测试场景
5. 点击 `模拟离线 24 小时`
6. 查看输出库存是否变成 `iron_plate x5`
7. 查看机器状态是否变成 `InputBlocked`

### 如果测试结果不对，优先检查这些地方

- `RecipeJsonById` 是否解析成功
- `MachineController.RecipeId` 是否和配方 ID 一致
- `InitialInventory` 是否真的灌到了第一台机器
- 快照文件是否被保存到了 `user://production_snapshot.json`
- 机器容量是否把输出卡死了

## 离线计算限制与补偿

### 最大离线时长

默认上限是：

```text
72 小时 = 259200 秒
```

对应字段：

```text
MaxOfflineSeconds
```

如果玩家离线超过这个时间，当前实现会直接裁剪到上限再计算。

### 浮点精度

当前使用：

- `float`
- `ProductionMath.Epsilon = 1e-4f`
- `ProductionMath.StopThreshold = 1e-3f`

这意味着：

- 不要用 `==` 判断时间相等
- 临近结束时的极小剩余时间会被直接收敛
- 更适合秒级或亚秒级工业周期

### 当前模型边界

当前版本有意保持在“批处理工业”范畴内，不处理：

- 连续流体流量
- 输送带上中途截流
- 机械臂搬运中的动画帧
- 实时电网波动

如果你后面要做这些系统，建议继续保持“事件驱动”，而不是回退到“离线逐帧重放”。

### 补偿策略建议

如果你想给离线玩家加保底或削减收益，可以在两处做：

#### 做法 A：修改离线时间

例如只按 80% 时间计算：

```csharp
float compensatedDt = rawDt * 0.8f;
var result = OfflineSimulationEngine.SimulateOffline(snapshots, compensatedDt);
```

#### 做法 B：修改最终产出

例如额外给 10% 奖励：

```csharp
result.TotalProduced["iron_plate"] += bonusAmount;
```

一般来说：

- 想影响所有中间状态，用做法 A
- 只想影响结算奖励，用做法 B

## 常见扩展方向

### 多机器串联

如果你有：

- 冶炼机产出铁板
- 装配机消耗铁板生产齿轮

那么可以通过 `OutputRoutes` 把上游机器的输出连到下游机器输入。当前引擎已经有路由处理逻辑，后续只要把路由数据真正配置起来即可。

### 多配方动态切换

你可以在 `MachineSnapshot` 上增加：

- 可选配方列表
- 当前切换策略
- 配方切换冷却

然后在 `ProcessImmediateMachine()` 内改成先选配方再尝试开工。

### 物流机器人

可以把机器人本身也当成事件源，事件类似：

- 出发
- 到达取货点
- 装货完成
- 到达投递点

这样离线恢复时依然只需要跳事件，不需要逐帧模拟机器人移动。

### 管道压力与流量限制

可以给 `MachineRoute` 增加：

- 最大吞吐
- 当前拥塞系数
- 流量损耗

然后把 `RouteToDownstream()` 从“瞬时转移”扩展成“按容量结算”。

## 常见问题

### 1. 场景能运行，但按钮没反应

优先检查：

- 根节点是否挂了 `ProductionLineManager.cs`
- 按钮节点名是否仍然是默认路径
- `_Ready()` 是否成功执行

### 2. 模拟后没有任何产出

优先检查：

- 配方是不是空的
- 输入物品 ID 是否和配方需要的 ID 完全一致
- 机器是否 `AutoStart = true`
- 输入缓存是否真的有货

### 3. 模拟后机器一直是 `OutputBlocked`

说明产物生成了，但输出写不出去。优先检查：

- `OutputCapacity`
- `PendingOutputBuffer`
- 下游路由是否存在
- 下游输入容量是否足够

### 4. 为什么离线 24 小时只产了 5 个铁板

因为这不是按时间上限硬产，而是按真实输入限制来算：

- 每轮需要 2 个铁锭
- 你只给了 10 个铁锭
- 所以最多只做 5 轮

### 5. 为什么代码里还保留了 `timeToInputDeplete` 和 `timeToOutputFull`

因为这是事件驱动框架的扩展点。当前批处理模型下，这两个事件会退化或与完成事件重合；以后如果你做连续物流模型，这两个接口就有用了。

## 关键代码入口索引

- 数据定义入口：
  - [ProductionData.cs](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/data/ProductionData.cs)
- 离线推演入口：
  - [OfflineSimulationEngine.cs](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/engine/OfflineSimulationEngine.cs)
- 单机运行时入口：
  - [MachineController.cs](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/runtime/MachineController.cs)
- 生产线管理入口：
  - [ProductionLineManager.cs](/C:/Users/daxingyi/Documents/auracole/scripts/industry_map/runtime/ProductionLineManager.cs)
- 测试场景：
  - [test_offline_production.tscn](/C:/Users/daxingyi/Documents/auracole/scenes/test_offline_production.tscn)

## 一句话总结怎么用

最小可用方式就是：

1. 在场景根节点挂 `ProductionLineManager`
2. 在子节点挂一个或多个 `MachineController`
3. 给管理器配置 `RecipeJsonById`
4. 给机器配置 `MachineId / RecipeId / Capacity`
5. 下线时调用 `SaveSnapshot()`
6. 上线时调用 `LoadAndSimulateOffline()`

如果你只是想先跑起来，直接打开：

- [test_offline_production.tscn](/C:/Users/daxingyi/Documents/auracole/scenes/test_offline_production.tscn)

按按钮测试就可以了。
