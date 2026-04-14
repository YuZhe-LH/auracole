using System;
using System.Collections.Generic;
using Godot;
using Auracole.IndustryMap.Data;

namespace Auracole.IndustryMap.Runtime;

/// <summary>
/// 场景中的单机控制节点，负责维护本地缓冲区和快照映射。
/// </summary>
[GlobalClass]
public partial class MachineController : Node2D
{
	/// <summary>
	/// 机器唯一标识，用于与快照结果匹配。
	/// </summary>
	[Export]
	public string MachineId { get; set; } = "machine_01";

	/// <summary>
	/// 机器显示名称。
	/// </summary>
	[Export]
	public string DisplayName { get; set; } = "基础冶炼机";

	/// <summary>
	/// 默认使用的配方标识。
	/// </summary>
	[Export]
	public string RecipeId { get; set; } = "smelt_iron_plate";

	/// <summary>
	/// 是否允许自动开工。
	/// </summary>
	[Export]
	public bool AutoStart { get; set; } = true;

	/// <summary>
	/// 稳定排序号，用于多机推演时保持确定性顺序。
	/// </summary>
	[Export]
	public int SortOrder { get; set; }

	/// <summary>
	/// 编辑器内配置的初始输入缓存区。
	/// </summary>
	[Export]
	public Godot.Collections.Dictionary<string, int> InitialInputBuffer { get; set; } = new();

	/// <summary>
	/// 编辑器内配置的初始输出缓存区。
	/// </summary>
	[Export]
	public Godot.Collections.Dictionary<string, int> InitialOutputBuffer { get; set; } = new();

	/// <summary>
	/// 输入缓存区容量上限。
	/// </summary>
	[Export]
	public Godot.Collections.Dictionary<string, int> InputCapacity { get; set; } = new();

	/// <summary>
	/// 输出缓存区容量上限。
	/// </summary>
	[Export]
	public Godot.Collections.Dictionary<string, int> OutputCapacity { get; set; } = new();

	/// <summary>
	/// 当前正在使用的配方。
	/// </summary>
	public Recipe CurrentRecipe { get; private set; } = new();

	/// <summary>
	/// 当前离散状态。
	/// </summary>
	public MachineState CurrentState { get; private set; } = MachineState.Idle;

	/// <summary>
	/// 当前已累计的加工进度，单位为秒。
	/// </summary>
	public float ProgressSeconds { get; private set; }

	private readonly Dictionary<string, int> _inputBuffer = new(StringComparer.Ordinal);
	private readonly Dictionary<string, int> _outputBuffer = new(StringComparer.Ordinal);
	private readonly Dictionary<string, int> _pendingOutputBuffer = new(StringComparer.Ordinal);
	private readonly List<MachineRoute> _outputRoutes = [];

	public override void _Ready()
	{
		ResetBuffersFromExports();
	}

	/// <summary>
	/// 为机器设置运行时配方。
	/// </summary>
	public void ConfigureRecipe(Recipe recipe)
	{
		CurrentRecipe = recipe.DeepClone();
	}

	/// <summary>
	/// 用编辑器导出的默认值重置机器缓冲区。
	/// </summary>
	public void ResetBuffersFromExports()
	{
		_inputBuffer.Clear();
		_outputBuffer.Clear();
		_pendingOutputBuffer.Clear();

		foreach (string itemId in InitialInputBuffer.Keys)
		{
			_inputBuffer[itemId] = InitialInputBuffer[itemId];
		}

		foreach (string itemId in InitialOutputBuffer.Keys)
		{
			_outputBuffer[itemId] = InitialOutputBuffer[itemId];
		}

		CurrentState = MachineState.Idle;
		ProgressSeconds = 0.0f;
	}

	/// <summary>
	/// 接收外部输入物料，返回实际接收数量。
	/// </summary>
	public int ReceiveInput(string itemId, int amount)
	{
		int accepted = ProductionMath.AddWithCapacity(_inputBuffer, ToNativeDictionary(InputCapacity), itemId, amount);
		if (accepted > 0 && CurrentState == MachineState.InputBlocked)
		{
			CurrentState = MachineState.Idle;
		}

		return accepted;
	}

	/// <summary>
	/// 取出当前全部输出缓存，并清空本地输出区。
	/// </summary>
	public Dictionary<string, int> TakeOutput()
	{
		Dictionary<string, int> extracted = new(_outputBuffer, StringComparer.Ordinal);
		_outputBuffer.Clear();
		return extracted;
	}

	/// <summary>
	/// 获取当前机器状态。
	/// </summary>
	public MachineState GetState()
	{
		return CurrentState;
	}

	/// <summary>
	/// 设置下游输出路由。
	/// </summary>
	public void SetOutputRoutes(IEnumerable<MachineRoute> routes)
	{
		_outputRoutes.Clear();
		_outputRoutes.AddRange(routes);
	}

	/// <summary>
	/// 将当前机器状态导出为可序列化快照。
	/// </summary>
	public MachineSnapshot BuildSnapshot()
	{
		return new MachineSnapshot
		{
			MachineId = MachineId,
			DisplayName = DisplayName,
			Recipe = CurrentRecipe.DeepClone(),
			State = CurrentState,
			ProgressSeconds = ProgressSeconds,
			AutoStart = AutoStart,
			InputBuffer = new Dictionary<string, int>(_inputBuffer, StringComparer.Ordinal),
			OutputBuffer = new Dictionary<string, int>(_outputBuffer, StringComparer.Ordinal),
			PendingOutputBuffer = new Dictionary<string, int>(_pendingOutputBuffer, StringComparer.Ordinal),
			InputCapacity = ToNativeDictionary(InputCapacity),
			OutputCapacity = ToNativeDictionary(OutputCapacity),
			OutputRoutes = new List<MachineRoute>(_outputRoutes.ConvertAll(route => route.DeepClone())),
			SortOrder = SortOrder
		};
	}

	/// <summary>
	/// 应用离线推演后的快照结果。
	/// </summary>
	public void ApplySnapshot(MachineSnapshot snapshot)
	{
		if (!string.Equals(snapshot.MachineId, MachineId, StringComparison.Ordinal))
		{
			return;
		}

		CurrentRecipe = snapshot.Recipe.DeepClone();
		CurrentState = snapshot.State;
		ProgressSeconds = snapshot.ProgressSeconds;

		ReplaceBuffer(_inputBuffer, snapshot.InputBuffer);
		ReplaceBuffer(_outputBuffer, snapshot.OutputBuffer);
		ReplaceBuffer(_pendingOutputBuffer, snapshot.PendingOutputBuffer);
	}

	/// <summary>
	/// 获取输入缓存区的副本，避免调用方直接修改内部状态。
	/// </summary>
	public Dictionary<string, int> GetInputBufferCopy()
	{
		return new Dictionary<string, int>(_inputBuffer, StringComparer.Ordinal);
	}

	/// <summary>
	/// 获取输出缓存区的副本。
	/// </summary>
	public Dictionary<string, int> GetOutputBufferCopy()
	{
		return new Dictionary<string, int>(_outputBuffer, StringComparer.Ordinal);
	}

	/// <summary>
	/// 获取待输出缓存区的副本。
	/// </summary>
	public Dictionary<string, int> GetPendingOutputCopy()
	{
		return new Dictionary<string, int>(_pendingOutputBuffer, StringComparer.Ordinal);
	}

	/// <summary>
	/// 用源字典完全覆盖目标缓冲区。
	/// </summary>
	private static void ReplaceBuffer(Dictionary<string, int> target, IReadOnlyDictionary<string, int> source)
	{
		target.Clear();
		foreach (KeyValuePair<string, int> pair in source)
		{
			target[pair.Key] = pair.Value;
		}
	}

	/// <summary>
	/// 将 Godot 泛型字典转换为标准 .NET 字典，便于推演逻辑使用。
	/// </summary>
	private static Dictionary<string, int> ToNativeDictionary(Godot.Collections.Dictionary<string, int> source)
	{
		Dictionary<string, int> result = new(StringComparer.Ordinal);
		foreach (string key in source.Keys)
		{
			result[key] = source[key];
		}

		return result;
	}
}
