using System;
using System.Collections.Generic;
using System.Linq;
using Godot;

namespace Auracole.IndustryMap.Data;

/// <summary>
/// 描述单台机器在离线推演中的离散状态。
/// </summary>
public enum MachineState
{
	Idle,
	Processing,
	InputBlocked,
	OutputBlocked
}

/// <summary>
/// 定义一种物品的基础静态数据。
/// </summary>
public sealed class Item
{
	/// <summary>
	/// 物品唯一标识。
	/// </summary>
	public string Id { get; set; } = string.Empty;

	/// <summary>
	/// 用于 UI 展示的人类可读名称。
	/// </summary>
	public string Name { get; set; } = string.Empty;

	/// <summary>
	/// 单个堆叠允许的最大数量。
	/// </summary>
	public int MaxStack { get; set; } = 999;

	/// <summary>
	/// 创建当前物品定义的深拷贝，避免运行时共享同一引用。
	/// </summary>
	public Item DeepClone()
	{
		return new Item
		{
			Id = Id,
			Name = Name,
			MaxStack = MaxStack
		};
	}
}

/// <summary>
/// 定义生产配方，包括单次周期时长、输入物料和输出物料。
/// </summary>
public sealed class Recipe
{
	/// <summary>
	/// 配方唯一标识。
	/// </summary>
	public string Id { get; set; } = string.Empty;

	/// <summary>
	/// 单次生产周期所需秒数。
	/// </summary>
	public float CycleTime { get; set; } = 1.0f;

	/// <summary>
	/// 单次开工时一次性消耗的输入物料。
	/// </summary>
	public Dictionary<string, int> Inputs { get; set; } = new(StringComparer.Ordinal);

	/// <summary>
	/// 单次完工时一次性生成的输出物料。
	/// </summary>
	public Dictionary<string, int> Outputs { get; set; } = new(StringComparer.Ordinal);

	/// <summary>
	/// 创建配方的深拷贝，确保字典不会被外部复用。
	/// </summary>
	public Recipe DeepClone()
	{
		return new Recipe
		{
			Id = Id,
			CycleTime = CycleTime,
			Inputs = new Dictionary<string, int>(Inputs, StringComparer.Ordinal),
			Outputs = new Dictionary<string, int>(Outputs, StringComparer.Ordinal)
		};
	}
}

/// <summary>
/// 描述一条输出路由，将某种产物发送到下游机器的指定输入口。
/// </summary>
public sealed class MachineRoute
{
	/// <summary>
	/// 要路由的物品标识。
	/// </summary>
	public string ItemId { get; set; } = string.Empty;

	/// <summary>
	/// 下游目标机器标识。
	/// </summary>
	public string TargetMachineId { get; set; } = string.Empty;

	/// <summary>
	/// 下游输入口物品标识；为空时沿用输出物品标识。
	/// </summary>
	public string TargetInputItemId { get; set; } = string.Empty;

	/// <summary>
	/// 路由优先级，值越小越优先。
	/// </summary>
	public int Priority { get; set; }

	/// <summary>
	/// 创建路由定义的深拷贝。
	/// </summary>
	public MachineRoute DeepClone()
	{
		return new MachineRoute
		{
			ItemId = ItemId,
			TargetMachineId = TargetMachineId,
			TargetInputItemId = TargetInputItemId,
			Priority = Priority
		};
	}
}

/// <summary>
/// 表示单台机器可被序列化的完整快照。
/// </summary>
public sealed class MachineSnapshot
{
	/// <summary>
	/// 机器唯一标识。
	/// </summary>
	public string MachineId { get; set; } = string.Empty;

	/// <summary>
	/// 机器显示名称。
	/// </summary>
	public string DisplayName { get; set; } = string.Empty;

	/// <summary>
	/// 当前绑定的生产配方。
	/// </summary>
	public Recipe Recipe { get; set; } = new();

	/// <summary>
	/// 当前离散状态。
	/// </summary>
	public MachineState State { get; set; } = MachineState.Idle;

	/// <summary>
	/// 当前配方已累计的加工进度，单位为秒。
	/// </summary>
	public float ProgressSeconds { get; set; }

	/// <summary>
	/// 是否允许在满足条件时自动开工。
	/// </summary>
	public bool AutoStart { get; set; } = true;

	/// <summary>
	/// 输入缓存区。
	/// </summary>
	public Dictionary<string, int> InputBuffer { get; set; } = new(StringComparer.Ordinal);

	/// <summary>
	/// 可直接被外部取走或继续路由的输出缓存区。
	/// </summary>
	public Dictionary<string, int> OutputBuffer { get; set; } = new(StringComparer.Ordinal);

	/// <summary>
	/// 因背压未能完全写入输出缓存区的暂存结果。
	/// </summary>
	public Dictionary<string, int> PendingOutputBuffer { get; set; } = new(StringComparer.Ordinal);

	/// <summary>
	/// 输入缓存区容量限制。
	/// </summary>
	public Dictionary<string, int> InputCapacity { get; set; } = new(StringComparer.Ordinal);

	/// <summary>
	/// 输出缓存区容量限制。
	/// </summary>
	public Dictionary<string, int> OutputCapacity { get; set; } = new(StringComparer.Ordinal);

	/// <summary>
	/// 输出到下游的路由表。
	/// </summary>
	public List<MachineRoute> OutputRoutes { get; set; } = [];

	/// <summary>
	/// 用于稳定排序，保证同条件下的处理顺序可重复。
	/// </summary>
	public int SortOrder { get; set; }

	/// <summary>
	/// 创建机器快照的深拷贝，避免离线推演污染场景原始数据。
	/// </summary>
	public MachineSnapshot DeepClone()
	{
		return new MachineSnapshot
		{
			MachineId = MachineId,
			DisplayName = DisplayName,
			Recipe = Recipe.DeepClone(),
			State = State,
			ProgressSeconds = ProgressSeconds,
			AutoStart = AutoStart,
			InputBuffer = new Dictionary<string, int>(InputBuffer, StringComparer.Ordinal),
			OutputBuffer = new Dictionary<string, int>(OutputBuffer, StringComparer.Ordinal),
			PendingOutputBuffer = new Dictionary<string, int>(PendingOutputBuffer, StringComparer.Ordinal),
			InputCapacity = new Dictionary<string, int>(InputCapacity, StringComparer.Ordinal),
			OutputCapacity = new Dictionary<string, int>(OutputCapacity, StringComparer.Ordinal),
			OutputRoutes = OutputRoutes.Select(route => route.DeepClone()).ToList(),
			SortOrder = SortOrder
		};
	}
}

/// <summary>
/// 封装一次离线推演的输出结果。
/// </summary>
public sealed class SimulationResult
{
	/// <summary>
	/// 推演结束后的机器快照集合。
	/// </summary>
	public MachineSnapshot[] FinalSnapshots { get; set; } = Array.Empty<MachineSnapshot>();

	/// <summary>
	/// 本次离线期间累计产出的物品统计。
	/// </summary>
	public Dictionary<string, int> TotalProduced { get; set; } = new(StringComparer.Ordinal);

	/// <summary>
	/// 实际被推演的秒数。
	/// </summary>
	public float SimulatedSeconds { get; set; }

	/// <summary>
	/// 被消费的定时事件数量。
	/// </summary>
	public int ProcessedTimedEvents { get; set; }

	/// <summary>
	/// 是否因为进入稳态或到达终止阈值而结束。
	/// </summary>
	public bool ReachedSteadyState { get; set; }
}

/// <summary>
/// 序列化到磁盘的顶层快照文件结构。
/// </summary>
public sealed class ProductionSnapshotFile
{
	/// <summary>
	/// 玩家下线时的 Unix 时间戳。
	/// </summary>
	public long LogoutUnixTime { get; set; }

	/// <summary>
	/// 下线瞬间的全部机器快照。
	/// </summary>
	public MachineSnapshot[] Machines { get; set; } = Array.Empty<MachineSnapshot>();

	/// <summary>
	/// 创建整个快照文件的深拷贝。
	/// </summary>
	public ProductionSnapshotFile DeepClone()
	{
		return new ProductionSnapshotFile
		{
			LogoutUnixTime = LogoutUnixTime,
			Machines = Machines.Select(machine => machine.DeepClone()).ToArray()
		};
	}
}

/// <summary>
/// 提供离线推演中共用的数值工具和缓冲区辅助方法。
/// </summary>
public static class ProductionMath
{
	/// <summary>
	/// 浮点数比较容差。
	/// </summary>
	public const float Epsilon = 1e-4f;

	/// <summary>
	/// 离线推演在该阈值以下视为可直接停止。
	/// </summary>
	public const float StopThreshold = 1e-3f;
	private const int UnlimitedCapacity = int.MaxValue / 4;

	/// <summary>
	/// 比较两个浮点数是否在容差范围内近似相等。
	/// </summary>
	public static bool NearlyEqual(float a, float b)
	{
		return MathF.Abs(a - b) <= Epsilon;
	}

	/// <summary>
	/// 判断浮点数是否近似为零。
	/// </summary>
	public static bool IsNearlyZero(float value)
	{
		return MathF.Abs(value) <= Epsilon;
	}

	/// <summary>
	/// 获取某种物品的容量上限；未配置时视为无限容量。
	/// </summary>
	public static int GetCapacity(Dictionary<string, int> capacityMap, string itemId)
	{
		return capacityMap.TryGetValue(itemId, out int capacity) ? capacity : UnlimitedCapacity;
	}

	/// <summary>
	/// 获取缓冲区中的物品数量；不存在时返回 0。
	/// </summary>
	public static int GetAmount(Dictionary<string, int> buffer, string itemId)
	{
		return buffer.TryGetValue(itemId, out int amount) ? amount : 0;
	}

	/// <summary>
	/// 设置缓冲区中某种物品的数量；小于等于 0 时直接移除键。
	/// </summary>
	public static void SetAmount(Dictionary<string, int> buffer, string itemId, int amount)
	{
		if (amount <= 0)
		{
			buffer.Remove(itemId);
			return;
		}

		buffer[itemId] = amount;
	}

	/// <summary>
	/// 向缓冲区写入指定数量的物品，并遵守容量限制，返回实际接收量。
	/// </summary>
	public static int AddWithCapacity(Dictionary<string, int> buffer, Dictionary<string, int> capacityMap, string itemId, int amount)
	{
		if (amount <= 0)
		{
			return 0;
		}

		int current = GetAmount(buffer, itemId);
		int capacity = GetCapacity(capacityMap, itemId);
		int accepted = Math.Min(amount, Math.Max(0, capacity - current));
		if (accepted > 0)
		{
			buffer[itemId] = current + accepted;
		}

		return accepted;
	}

	/// <summary>
	/// 从缓冲区中精确扣除指定数量的物品。
	/// </summary>
	public static void RemoveExact(Dictionary<string, int> buffer, string itemId, int amount)
	{
		if (amount <= 0)
		{
			return;
		}

		int current = GetAmount(buffer, itemId);
		SetAmount(buffer, itemId, Math.Max(0, current - amount));
	}

	/// <summary>
	/// 判断缓冲区是否满足一组输入需求。
	/// </summary>
	public static bool HasRequiredItems(Dictionary<string, int> buffer, IReadOnlyDictionary<string, int> requirement)
	{
		foreach (KeyValuePair<string, int> pair in requirement)
		{
			if (GetAmount(buffer, pair.Key) < pair.Value)
			{
				return false;
			}
		}

		return true;
	}

	/// <summary>
	/// 将库存字典格式化为适合 UI 日志展示的文本。
	/// </summary>
	public static string FormatInventory(IReadOnlyDictionary<string, int> inventory)
	{
		if (inventory.Count == 0)
		{
			return "0";
		}

		return string.Join(", ", inventory.OrderBy(pair => pair.Key, StringComparer.Ordinal)
			.Select(pair => $"{pair.Key} x{pair.Value}"));
	}
}

/// <summary>
/// 负责将运行时快照与 Godot 可序列化字典结构互相转换。
/// </summary>
public static class ProductionSerialization
{
	/// <summary>
	/// 将顶层快照文件转换为 Godot 字典，便于写入 JSON。
	/// </summary>
	public static Godot.Collections.Dictionary SerializeSnapshotFile(ProductionSnapshotFile snapshotFile)
	{
		Godot.Collections.Array machines = [];
		foreach (MachineSnapshot machine in snapshotFile.Machines)
		{
			machines.Add(SerializeMachineSnapshot(machine));
		}

		return new Godot.Collections.Dictionary
		{
			{ "logout_unix_time", snapshotFile.LogoutUnixTime },
			{ "machines", machines }
		};
	}

	/// <summary>
	/// 从 Godot 字典恢复顶层快照文件。
	/// </summary>
	public static ProductionSnapshotFile DeserializeSnapshotFile(Godot.Collections.Dictionary dictionary)
	{
		Godot.Collections.Array machineArray = dictionary.ContainsKey("machines")
			? ((Variant)dictionary["machines"]).AsGodotArray()
			: [];

		List<MachineSnapshot> machines = new(machineArray.Count);
		foreach (Variant machineVariant in machineArray)
		{
			machines.Add(DeserializeMachineSnapshot(machineVariant.AsGodotDictionary()));
		}

		return new ProductionSnapshotFile
		{
			LogoutUnixTime = dictionary.ContainsKey("logout_unix_time")
				? ((Variant)dictionary["logout_unix_time"]).AsInt64()
				: 0,
			Machines = machines.ToArray()
		};
	}

	/// <summary>
	/// 将单台机器快照转换为 Godot 字典。
	/// </summary>
	public static Godot.Collections.Dictionary SerializeMachineSnapshot(MachineSnapshot snapshot)
	{
		Godot.Collections.Array routes = [];
		foreach (MachineRoute route in snapshot.OutputRoutes.OrderBy(route => route.Priority).ThenBy(route => route.TargetMachineId, StringComparer.Ordinal))
		{
			routes.Add(new Godot.Collections.Dictionary
			{
				{ "item_id", route.ItemId },
				{ "target_machine_id", route.TargetMachineId },
				{ "target_input_item_id", route.TargetInputItemId },
				{ "priority", route.Priority }
			});
		}

		return new Godot.Collections.Dictionary
		{
			{ "machine_id", snapshot.MachineId },
			{ "display_name", snapshot.DisplayName },
			{ "recipe", SerializeRecipe(snapshot.Recipe) },
			{ "state", snapshot.State.ToString() },
			{ "progress_seconds", snapshot.ProgressSeconds },
			{ "auto_start", snapshot.AutoStart },
			{ "input_buffer", SerializeStringIntDictionary(snapshot.InputBuffer) },
			{ "output_buffer", SerializeStringIntDictionary(snapshot.OutputBuffer) },
			{ "pending_output_buffer", SerializeStringIntDictionary(snapshot.PendingOutputBuffer) },
			{ "input_capacity", SerializeStringIntDictionary(snapshot.InputCapacity) },
			{ "output_capacity", SerializeStringIntDictionary(snapshot.OutputCapacity) },
			{ "output_routes", routes },
			{ "sort_order", snapshot.SortOrder }
		};
	}

	/// <summary>
	/// 从 Godot 字典恢复单台机器快照。
	/// </summary>
	public static MachineSnapshot DeserializeMachineSnapshot(Godot.Collections.Dictionary dictionary)
	{
		List<MachineRoute> routes = [];
		Godot.Collections.Array routeArray = dictionary.ContainsKey("output_routes")
			? ((Variant)dictionary["output_routes"]).AsGodotArray()
			: [];

		foreach (Variant routeVariant in routeArray)
		{
			Godot.Collections.Dictionary routeDict = routeVariant.AsGodotDictionary();
			routes.Add(new MachineRoute
			{
				ItemId = routeDict.ContainsKey("item_id") ? ((Variant)routeDict["item_id"]).AsString() : string.Empty,
				TargetMachineId = routeDict.ContainsKey("target_machine_id") ? ((Variant)routeDict["target_machine_id"]).AsString() : string.Empty,
				TargetInputItemId = routeDict.ContainsKey("target_input_item_id") ? ((Variant)routeDict["target_input_item_id"]).AsString() : string.Empty,
				Priority = routeDict.ContainsKey("priority") ? ((Variant)routeDict["priority"]).AsInt32() : 0
			});
		}

		string stateName = dictionary.ContainsKey("state") ? ((Variant)dictionary["state"]).AsString() : nameof(MachineState.Idle);
		if (!Enum.TryParse(stateName, true, out MachineState machineState))
		{
			machineState = MachineState.Idle;
		}

		return new MachineSnapshot
		{
			MachineId = dictionary.ContainsKey("machine_id") ? ((Variant)dictionary["machine_id"]).AsString() : string.Empty,
			DisplayName = dictionary.ContainsKey("display_name") ? ((Variant)dictionary["display_name"]).AsString() : string.Empty,
			Recipe = dictionary.ContainsKey("recipe") ? DeserializeRecipe(((Variant)dictionary["recipe"]).AsGodotDictionary()) : new Recipe(),
			State = machineState,
			ProgressSeconds = dictionary.ContainsKey("progress_seconds") ? ((Variant)dictionary["progress_seconds"]).AsSingle() : 0.0f,
			AutoStart = !dictionary.ContainsKey("auto_start") || ((Variant)dictionary["auto_start"]).AsBool(),
			InputBuffer = DeserializeStringIntDictionary(dictionary, "input_buffer"),
			OutputBuffer = DeserializeStringIntDictionary(dictionary, "output_buffer"),
			PendingOutputBuffer = DeserializeStringIntDictionary(dictionary, "pending_output_buffer"),
			InputCapacity = DeserializeStringIntDictionary(dictionary, "input_capacity"),
			OutputCapacity = DeserializeStringIntDictionary(dictionary, "output_capacity"),
			OutputRoutes = routes,
			SortOrder = dictionary.ContainsKey("sort_order") ? ((Variant)dictionary["sort_order"]).AsInt32() : 0
		};
	}

	/// <summary>
	/// 将配方对象序列化为 Godot 字典。
	/// </summary>
	public static Godot.Collections.Dictionary SerializeRecipe(Recipe recipe)
	{
		return new Godot.Collections.Dictionary
		{
			{ "id", recipe.Id },
			{ "cycle_time", recipe.CycleTime },
			{ "inputs", SerializeStringIntDictionary(recipe.Inputs) },
			{ "outputs", SerializeStringIntDictionary(recipe.Outputs) }
		};
	}

	/// <summary>
	/// 从 Godot 字典恢复配方对象。
	/// </summary>
	public static Recipe DeserializeRecipe(Godot.Collections.Dictionary dictionary)
	{
		return new Recipe
		{
			Id = dictionary.ContainsKey("id") ? ((Variant)dictionary["id"]).AsString() : string.Empty,
			CycleTime = dictionary.ContainsKey("cycle_time") ? ((Variant)dictionary["cycle_time"]).AsSingle() : 1.0f,
			Inputs = DeserializeStringIntDictionary(dictionary, "inputs"),
			Outputs = DeserializeStringIntDictionary(dictionary, "outputs")
		};
	}

	/// <summary>
	/// 序列化字符串到整数的字典，并按键排序确保输出稳定。
	/// </summary>
	public static Godot.Collections.Dictionary SerializeStringIntDictionary(IReadOnlyDictionary<string, int> dictionary)
	{
		Godot.Collections.Dictionary serialized = [];
		foreach (KeyValuePair<string, int> pair in dictionary.OrderBy(pair => pair.Key, StringComparer.Ordinal))
		{
			serialized[pair.Key] = pair.Value;
		}

		return serialized;
	}

	/// <summary>
	/// 从根字典的指定键读取字符串到整数的字典。
	/// </summary>
	public static Dictionary<string, int> DeserializeStringIntDictionary(Godot.Collections.Dictionary root, string key)
	{
		if (!root.ContainsKey(key))
		{
			return new Dictionary<string, int>(StringComparer.Ordinal);
		}

		return DeserializeStringIntDictionary(((Variant)root[key]).AsGodotDictionary());
	}

	/// <summary>
	/// 直接从 Godot 字典恢复字符串到整数的字典。
	/// </summary>
	public static Dictionary<string, int> DeserializeStringIntDictionary(Godot.Collections.Dictionary dictionary)
	{
		Dictionary<string, int> result = new(StringComparer.Ordinal);
		foreach (Variant keyVariant in dictionary.Keys)
		{
			string key = keyVariant.AsString();
			result[key] = ((Variant)dictionary[key]).AsInt32();
		}

		return result;
	}
}
