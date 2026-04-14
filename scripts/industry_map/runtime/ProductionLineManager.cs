using System;
using System.Collections.Generic;
using System.Linq;
using Godot;
using Auracole.IndustryMap.Data;
using Auracole.IndustryMap.Engine;

namespace Auracole.IndustryMap.Runtime;

/// <summary>
/// 生产线运行时入口，负责快照保存、离线推演和结果回写场景。
/// </summary>
[GlobalClass]
public partial class ProductionLineManager : Control
{
	/// <summary>
	/// 当生产线数据被更新后发出，供 UI 或其他系统刷新。
	/// </summary>
	[Signal]
	public delegate void ProductionUpdatedEventHandler();

	/// <summary>
	/// 配方标识到 JSON 文本的映射，用于在编辑器中直接配置默认配方。
	/// </summary>
	[Export]
	public Godot.Collections.Dictionary<string, string> RecipeJsonById { get; set; } = new();

	/// <summary>
	/// 测试场景启动时灌入第一台机器的初始库存。
	/// </summary>
	[Export]
	public Godot.Collections.Dictionary<string, int> InitialInventory { get; set; } = new();

	/// <summary>
	/// 单次离线恢复允许推演的最大秒数。
	/// </summary>
	[Export(PropertyHint.Range, "0,259200,1")]
	public float MaxOfflineSeconds { get; set; } = 72.0f * 3600.0f;

	/// <summary>
	/// 需要纳入管理的机器节点路径列表；为空时自动搜索子节点。
	/// </summary>
	[Export]
	public Godot.Collections.Array<NodePath> MachinePaths { get; set; } = [];

	private const string SnapshotPath = "user://production_snapshot.json";
	private readonly Dictionary<string, Recipe> _recipes = new(StringComparer.Ordinal);
	private readonly List<MachineController> _machines = [];

	private Label? _inputInventoryLabel;
	private Label? _outputInventoryLabel;
	private Label? _machineStateLabel;
	private Label? _offlineDurationLabel;
	private Label? _logLabel;
	private Button? _simulateButton;
	private Button? _manualFeedButton;
	private Button? _saveQuitButton;
	private float _lastOfflineSeconds;

	public override void _Ready()
	{
		CacheUiReferences();
		EnsureDefaultConfiguration();
		BuildRecipeCache();
		DiscoverMachines();
		ApplyInitialRecipesAndInventory();
		WireButtons();
		UpdateUiFromScene();
		WriteLog("就绪：已初始化离线工业生产线测试场景。");
	}

	/// <summary>
	/// 将当前生产线状态保存为离线快照文件。
	/// </summary>
	public void SaveSnapshot()
	{
		ProductionSnapshotFile snapshotFile = new()
		{
			LogoutUnixTime = GetAuthoritativeUnixSeconds(),
			Machines = _machines.Select(machine => machine.BuildSnapshot()).ToArray()
		};

		string json = Json.Stringify(ProductionSerialization.SerializeSnapshotFile(snapshotFile), "\t", true);
		using FileAccess file = FileAccess.Open(SnapshotPath, FileAccess.ModeFlags.Write);
		file.StoreString(json);
		WriteLog($"快照已保存到 {SnapshotPath}");
	}

	/// <summary>
	/// 按默认逻辑读取快照并执行离线推演。
	/// </summary>
	public void LoadAndSimulateOffline()
	{
		LoadAndSimulateOffline(-1.0f);
	}

	/// <summary>
	/// 读取快照并执行离线推演；可通过参数覆盖离线时长，便于测试。
	/// </summary>
	public void LoadAndSimulateOffline(float overrideOfflineSeconds)
	{
		ProductionSnapshotFile snapshotFile = TryLoadSnapshotFile() ?? new ProductionSnapshotFile
		{
			LogoutUnixTime = GetAuthoritativeUnixSeconds(),
			Machines = _machines.Select(machine => machine.BuildSnapshot()).ToArray()
		};

		// 正常流程应由服务端或可信时间源提供离线时长；测试场景允许手工覆盖。
		float elapsedSeconds = overrideOfflineSeconds >= 0.0f
			? overrideOfflineSeconds
			: MathF.Max(0.0f, GetAuthoritativeUnixSeconds() - snapshotFile.LogoutUnixTime);
		elapsedSeconds = MathF.Min(elapsedSeconds, MaxOfflineSeconds);
		_lastOfflineSeconds = elapsedSeconds;

		SimulationResult result = OfflineSimulationEngine.SimulateOffline(snapshotFile.Machines, elapsedSeconds);
		ApplyResultToScene(result);
		EmitSignal(SignalName.ProductionUpdated);
	}

	/// <summary>
	/// 将离线推演结果回写到场景中的各台机器，并刷新 UI。
	/// </summary>
	public void ApplyResultToScene(SimulationResult result)
	{
		Dictionary<string, MachineSnapshot> resultById = result.FinalSnapshots
			.ToDictionary(snapshot => snapshot.MachineId, StringComparer.Ordinal);

		foreach (MachineController machine in _machines)
		{
			if (resultById.TryGetValue(machine.MachineId, out MachineSnapshot? snapshot))
			{
				machine.ApplySnapshot(snapshot);
			}
		}

		UpdateUiFromScene();
		string producedText = ProductionMath.FormatInventory(result.TotalProduced);
		WriteLog($"离线推演完成：{result.SimulatedSeconds:0.###} 秒，事件数 {result.ProcessedTimedEvents}，累计产出 {producedText}");
	}

	/// <summary>
	/// 保存快照后退出当前运行场景。
	/// </summary>
	public void SaveSnapshotAndQuit()
	{
		SaveSnapshot();
		GetTree().Quit();
	}

	/// <summary>
	/// 缓存测试场景中的 UI 节点引用。
	/// </summary>
	private void CacheUiReferences()
	{
		_inputInventoryLabel = GetNodeOrNull<Label>("TopBar/InputInventoryLabel");
		_outputInventoryLabel = GetNodeOrNull<Label>("TopBar/OutputInventoryLabel");
		_machineStateLabel = GetNodeOrNull<Label>("TopBar/MachineStateLabel");
		_offlineDurationLabel = GetNodeOrNull<Label>("TopBar/OfflineDurationLabel");
		_logLabel = GetNodeOrNull<Label>("LogLabel");
		_simulateButton = GetNodeOrNull<Button>("ActionPanel/Simulate24HoursButton");
		_manualFeedButton = GetNodeOrNull<Button>("ActionPanel/ManualFeedButton");
		_saveQuitButton = GetNodeOrNull<Button>("ActionPanel/SaveAndQuitButton");
	}

	/// <summary>
	/// 在编辑器未配置时补齐一套最小可运行的默认配方和库存。
	/// </summary>
	private void EnsureDefaultConfiguration()
	{
		if (RecipeJsonById.Count == 0)
		{
			RecipeJsonById["smelt_iron_plate"] = Json.Stringify(new Godot.Collections.Dictionary
			{
				{ "id", "smelt_iron_plate" },
				{ "cycle_time", 5.0f },
				{ "inputs", new Godot.Collections.Dictionary { { "iron_ingot", 2 } } },
				{ "outputs", new Godot.Collections.Dictionary { { "iron_plate", 1 } } }
			}, string.Empty, true);
		}

		if (InitialInventory.Count == 0)
		{
			InitialInventory["iron_ingot"] = 10;
		}
	}

	/// <summary>
	/// 将导出的 JSON 配方配置解析为运行时缓存。
	/// </summary>
	private void BuildRecipeCache()
	{
		_recipes.Clear();
		foreach (string recipeId in RecipeJsonById.Keys.OrderBy(key => key, StringComparer.Ordinal))
		{
			string json = RecipeJsonById[recipeId];
			Variant parsed = Json.ParseString(json);
			Recipe recipe = parsed.VariantType == Variant.Type.Dictionary
				? ProductionSerialization.DeserializeRecipe(parsed.AsGodotDictionary())
				: new Recipe { Id = recipeId };
			if (string.IsNullOrWhiteSpace(recipe.Id))
			{
				recipe.Id = recipeId;
			}

			_recipes[recipe.Id] = recipe;
		}
	}

	/// <summary>
	/// 发现并缓存需要纳入生产线管理的机器节点。
	/// </summary>
	private void DiscoverMachines()
	{
		_machines.Clear();
		if (MachinePaths.Count > 0)
		{
			foreach (NodePath machinePath in MachinePaths)
			{
				MachineController? machine = GetNodeOrNull<MachineController>(machinePath);
				if (machine != null)
				{
					_machines.Add(machine);
				}
			}
		}

		if (_machines.Count == 0)
		{
			foreach (Node child in GetChildren())
			{
				if (child is MachineController machine)
				{
					_machines.Add(machine);
				}
			}
		}
	}

	/// <summary>
	/// 为机器注入默认配方，并把初始库存送到第一台机器。
	/// </summary>
	private void ApplyInitialRecipesAndInventory()
	{
		if (_machines.Count == 0 || _recipes.Count == 0)
		{
			return;
		}

		Recipe fallbackRecipe = _recipes.Values.OrderBy(recipe => recipe.Id, StringComparer.Ordinal).First();
		for (int index = 0; index < _machines.Count; index += 1)
		{
			MachineController machine = _machines[index];
			Recipe recipe = _recipes.TryGetValue(machine.RecipeId, out Recipe? configuredRecipe)
				? configuredRecipe
				: fallbackRecipe;

			machine.ConfigureRecipe(recipe);
			if (index == 0)
			{
				foreach (string itemId in InitialInventory.Keys)
				{
					machine.ReceiveInput(itemId, InitialInventory[itemId]);
				}
			}
		}
	}

	/// <summary>
	/// 绑定测试场景按钮事件和刷新信号。
	/// </summary>
	private void WireButtons()
	{
		if (_simulateButton != null)
		{
			_simulateButton.Pressed += () => LoadAndSimulateOffline(86400.0f);
		}

		if (_manualFeedButton != null)
		{
			_manualFeedButton.Pressed += HandleManualFeedPressed;
		}

		if (_saveQuitButton != null)
		{
			_saveQuitButton.Pressed += SaveSnapshotAndQuit;
		}

		ProductionUpdated += UpdateUiFromScene;
	}

	/// <summary>
	/// 测试按钮：向第一台机器手动投放铁锭。
	/// </summary>
	private void HandleManualFeedPressed()
	{
		if (_machines.Count == 0)
		{
			WriteLog("没有可进料的机器节点。");
			return;
		}

		int accepted = _machines[0].ReceiveInput("iron_ingot", 10);
		UpdateUiFromScene();
		WriteLog($"手动进料：iron_ingot x{accepted}");
	}

	/// <summary>
	/// 尝试从用户目录读取离线快照文件。
	/// </summary>
	private ProductionSnapshotFile? TryLoadSnapshotFile()
	{
		if (!FileAccess.FileExists(SnapshotPath))
		{
			WriteLog("未找到快照文件，改为使用当前场景状态作为离线推演起点。");
			return null;
		}

		using FileAccess file = FileAccess.Open(SnapshotPath, FileAccess.ModeFlags.Read);
		string jsonText = file.GetAsText();
		Variant parsed = Json.ParseString(jsonText);
		if (parsed.VariantType != Variant.Type.Dictionary)
		{
			WriteLog("快照 JSON 解析失败，改为使用当前场景状态。");
			return null;
		}

		return ProductionSerialization.DeserializeSnapshotFile(parsed.AsGodotDictionary());
	}

	/// <summary>
	/// 用当前场景中的机器数据刷新顶部状态栏。
	/// </summary>
	private void UpdateUiFromScene()
	{
		MachineController? primaryMachine = _machines.FirstOrDefault();
		if (primaryMachine == null)
		{
			return;
		}

		if (_inputInventoryLabel != null)
		{
			_inputInventoryLabel.Text = $"输入库存: {ProductionMath.FormatInventory(primaryMachine.GetInputBufferCopy())}";
		}

		if (_outputInventoryLabel != null)
		{
			_outputInventoryLabel.Text = $"输出库存: {ProductionMath.FormatInventory(primaryMachine.GetOutputBufferCopy())}";
		}

		if (_machineStateLabel != null)
		{
			_machineStateLabel.Text = $"机器状态: {primaryMachine.GetState()}";
		}

		if (_offlineDurationLabel != null)
		{
			_offlineDurationLabel.Text = $"离线时长: {_lastOfflineSeconds:0}s";
		}
	}

	/// <summary>
	/// 同步更新底部日志标签，并写入 Godot 控制台。
	/// </summary>
	private void WriteLog(string message)
	{
		if (_logLabel != null)
		{
			_logLabel.Text = message;
		}

		GD.Print(message);
	}

	private static long GetAuthoritativeUnixSeconds()
	{
		// 运行时允许替换为服务端时间源；核心推演引擎不读取系统时间，保证可重复推演。
		return DateTimeOffset.UtcNow.ToUnixTimeSeconds();
	}
}
