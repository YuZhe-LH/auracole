using System;
using System.Collections.Generic;
using System.Linq;
using Auracole.IndustryMap.Data;

namespace Auracole.IndustryMap.Engine;

/// <summary>
/// 离线工业生产线的事件驱动推演引擎。
/// </summary>
public static class OfflineSimulationEngine
{
	/// <summary>
	/// 根据一组机器快照和离线秒数，计算离线结束后的最终状态。
	/// </summary>
	/// <param name="snapshots">离线开始时的机器快照。</param>
	/// <param name="deltaSeconds">需要推演的离线秒数。</param>
	/// <returns>包含最终机器快照和累计产出的推演结果。</returns>
	public static SimulationResult SimulateOffline(MachineSnapshot[] snapshots, float deltaSeconds)
	{
		float clampedDelta = MathF.Max(0.0f, deltaSeconds);
		MachineSnapshot[] workingCopies = snapshots.Select(snapshot => snapshot.DeepClone()).ToArray();
		if (workingCopies.Length == 0 || clampedDelta <= ProductionMath.StopThreshold)
		{
			return new SimulationResult
			{
				FinalSnapshots = workingCopies,
				SimulatedSeconds = clampedDelta,
				ReachedSteadyState = true
			};
		}

		SimulationContext context = new(workingCopies, clampedDelta);
		context.Initialize();

		// 时间复杂度：初始化 O(N log N)，每次事件处理 O(log N + E_local)。
		// 这里只在离散事件点推进逻辑时钟，不做 while(dt--) 的逐帧离线回放。
		while (context.RemainingSeconds > ProductionMath.StopThreshold)
		{
			context.ProcessImmediateQueue();

			if (!context.TryPeekNextTimedEvent(out TimedMachineEvent nextEvent))
			{
				context.MarkSteadyState();
				break;
			}

			float nextEventDt = nextEvent.AbsoluteTime - context.ElapsedSeconds;
			if (nextEventDt <= ProductionMath.Epsilon)
			{
				context.PopTimedEvent();
				context.ResolveCompletion(nextEvent.MachineId);
				continue;
			}

			if (nextEventDt >= context.RemainingSeconds - ProductionMath.StopThreshold)
			{
				context.AdvanceToEndWithoutNewEvent();
				context.ProcessImmediateQueue();
				return context.BuildResult();
			}

			context.AdvanceBy(nextEventDt);
			context.PopTimedEvent();
			context.ResolveCompletion(nextEvent.MachineId);
		}

		context.AdvanceToEndWithoutNewEvent();
		context.ProcessImmediateQueue();
		return context.BuildResult();
	}

	/// <summary>
	/// 单次推演所需的内部上下文，集中维护机器状态、事件队列和逻辑时钟。
	/// </summary>
	private sealed class SimulationContext
	{
		// 按机器标识组织运行时状态，便于快速定位上下游节点。
		private readonly Dictionary<string, MachineRuntimeState> _machines;

		// 定时事件队列只保存“未来会发生完成/阻塞切换”的机器。
		private readonly PriorityQueue<TimedMachineEvent, float> _timedEvents = new();

		// 即时队列用于处理由路由、解阻塞等操作触发的零时延状态变化。
		private readonly Queue<string> _immediateQueue = new();
		private readonly HashSet<string> _immediateSet = new(StringComparer.Ordinal);
		private readonly Dictionary<string, int> _totalProduced = new(StringComparer.Ordinal);
		private readonly float _targetSeconds;
		private bool _steadyState;

		public SimulationContext(IEnumerable<MachineSnapshot> snapshots, float targetSeconds)
		{
			_targetSeconds = targetSeconds;
			_machines = snapshots
				.Select(snapshot => new MachineRuntimeState(snapshot))
				.ToDictionary(runtime => runtime.Snapshot.MachineId, StringComparer.Ordinal);
		}

		public float ElapsedSeconds { get; private set; }
		public float RemainingSeconds => MathF.Max(0.0f, _targetSeconds - ElapsedSeconds);
		public int ProcessedTimedEvents { get; private set; }

		/// <summary>
		/// 初始化所有机器，并把首批即时处理任务加入队列。
		/// </summary>
		public void Initialize()
		{
			foreach (MachineRuntimeState runtime in OrderedMachines())
			{
				runtime.SynchronizeProgressTo(0.0f);
				EnqueueImmediate(runtime.Snapshot.MachineId);
			}

			ProcessImmediateQueue();
		}

		/// <summary>
		/// 标记系统已经进入稳态，没有新的事件可发生。
		/// </summary>
		public void MarkSteadyState()
		{
			_steadyState = true;
		}

		/// <summary>
		/// 将逻辑时钟推进指定秒数。
		/// </summary>
		public void AdvanceBy(float deltaSeconds)
		{
			ElapsedSeconds = MathF.Min(_targetSeconds, ElapsedSeconds + MathF.Max(0.0f, deltaSeconds));
		}

		/// <summary>
		/// 直接把逻辑时钟推进到离线时间上限。
		/// </summary>
		public void AdvanceToEndWithoutNewEvent()
		{
			ElapsedSeconds = _targetSeconds;
		}

		/// <summary>
		/// 查看下一个仍然有效的定时事件。
		/// </summary>
		public bool TryPeekNextTimedEvent(out TimedMachineEvent timedEvent)
		{
			while (_timedEvents.TryPeek(out TimedMachineEvent candidate, out _))
			{
				if (!IsTimedEventStillValid(candidate))
				{
					_timedEvents.Dequeue();
					continue;
				}

				timedEvent = candidate;
				return true;
			}

			timedEvent = default;
			return false;
		}

		/// <summary>
		/// 弹出一个定时事件并统计已处理数量。
		/// </summary>
		public void PopTimedEvent()
		{
			if (_timedEvents.TryDequeue(out _, out _))
			{
				ProcessedTimedEvents += 1;
			}
		}

		/// <summary>
		/// 处理某台机器的“加工完成”事件。
		/// </summary>
		public void ResolveCompletion(string machineId)
		{
			if (!_machines.TryGetValue(machineId, out MachineRuntimeState? runtime))
			{
				return;
			}

			runtime.SynchronizeProgressTo(ElapsedSeconds);
			if (runtime.Snapshot.State != MachineState.Processing)
			{
				return;
			}

			Recipe recipe = runtime.Snapshot.Recipe;
			runtime.Snapshot.ProgressSeconds = recipe.CycleTime;
			// 完成时一次性生成整批产物，保证批处理语义的确定性。
			Dictionary<string, int> completedBatch = new(StringComparer.Ordinal);
			foreach (KeyValuePair<string, int> output in recipe.Outputs)
			{
				if (output.Value <= 0)
				{
					continue;
				}

				completedBatch[output.Key] = output.Value;
				int currentTotal = ProductionMath.GetAmount(_totalProduced, output.Key);
				ProductionMath.SetAmount(_totalProduced, output.Key, currentTotal + output.Value);
			}

			runtime.Snapshot.State = MachineState.Idle;
			runtime.Snapshot.ProgressSeconds = 0.0f;
			runtime.AnchorElapsedSeconds = ElapsedSeconds;
			runtime.AnchorProgressSeconds = 0.0f;
			FlushProducedOutputs(runtime, completedBatch);
			EnqueueImmediate(machineId);
		}

		/// <summary>
		/// 持续处理所有零时延状态变化，直到系统暂时稳定。
		/// </summary>
		public void ProcessImmediateQueue()
		{
			while (_immediateQueue.Count > 0)
			{
				string machineId = _immediateQueue.Dequeue();
				_immediateSet.Remove(machineId);
				ProcessImmediateMachine(machineId);
			}
		}

		/// <summary>
		/// 汇总当前上下文并导出最终推演结果。
		/// </summary>
		public SimulationResult BuildResult()
		{
			foreach (MachineRuntimeState runtime in OrderedMachines())
			{
				runtime.SynchronizeProgressTo(ElapsedSeconds);
			}

			return new SimulationResult
			{
				FinalSnapshots = OrderedMachines().Select(runtime => runtime.Snapshot.DeepClone()).ToArray(),
				TotalProduced = new Dictionary<string, int>(_totalProduced, StringComparer.Ordinal),
				SimulatedSeconds = ElapsedSeconds,
				ProcessedTimedEvents = ProcessedTimedEvents,
				ReachedSteadyState = _steadyState || RemainingSeconds <= ProductionMath.StopThreshold
			};
		}

		/// <summary>
		/// 返回稳定顺序的机器集合，保证相同输入下处理顺序一致。
		/// </summary>
		private IEnumerable<MachineRuntimeState> OrderedMachines()
		{
			return _machines.Values
				.OrderBy(runtime => runtime.Snapshot.SortOrder)
				.ThenBy(runtime => runtime.Snapshot.MachineId, StringComparer.Ordinal);
		}

		/// <summary>
		/// 处理某台机器的即时状态变化，例如路由后被唤醒、解除背压或尝试开工。
		/// </summary>
		private void ProcessImmediateMachine(string machineId)
		{
			if (!_machines.TryGetValue(machineId, out MachineRuntimeState? runtime))
			{
				return;
			}

			runtime.SynchronizeProgressTo(ElapsedSeconds);
			// 先尝试排空历史输出，再处理因背压遗留的待写入结果。
			FlushOutputBuffer(runtime);
			FlushPendingOutputs(runtime);

			if (runtime.Snapshot.State == MachineState.Processing)
			{
				ScheduleTimedEvent(runtime);
				return;
			}

			if (runtime.Snapshot.PendingOutputBuffer.Count > 0)
			{
				runtime.Snapshot.State = MachineState.OutputBlocked;
				return;
			}

			if (!runtime.Snapshot.AutoStart || string.IsNullOrWhiteSpace(runtime.Snapshot.Recipe.Id))
			{
				runtime.Snapshot.State = MachineState.Idle;
				return;
			}

			if (TryStartProcessing(runtime))
			{
				return;
			}

			runtime.Snapshot.State = HasAnyInputDeficit(runtime.Snapshot)
				? MachineState.InputBlocked
				: MachineState.Idle;
		}

		/// <summary>
		/// 当输入满足条件时让机器开工，并为其登记下一个定时事件。
		/// </summary>
		private bool TryStartProcessing(MachineRuntimeState runtime)
		{
			if (!ProductionMath.HasRequiredItems(runtime.Snapshot.InputBuffer, runtime.Snapshot.Recipe.Inputs))
			{
				return false;
			}

			// 批处理模型在开工瞬间一次性扣料，不在加工途中持续消耗。
			foreach (KeyValuePair<string, int> input in runtime.Snapshot.Recipe.Inputs)
			{
				ProductionMath.RemoveExact(runtime.Snapshot.InputBuffer, input.Key, input.Value);
			}

			runtime.Snapshot.State = MachineState.Processing;
			runtime.Snapshot.ProgressSeconds = 0.0f;
			runtime.AnchorElapsedSeconds = ElapsedSeconds;
			runtime.AnchorProgressSeconds = 0.0f;
			ScheduleTimedEvent(runtime);
			return true;
		}

		/// <summary>
		/// 为正在加工的机器登记下一个有效定时事件。
		/// </summary>
		private void ScheduleTimedEvent(MachineRuntimeState runtime)
		{
			float nextEventDt = ComputeNextEventDt(runtime);
			if (float.IsPositiveInfinity(nextEventDt))
			{
				return;
			}

			runtime.TimedEventVersion += 1;
			float absoluteTime = ElapsedSeconds + MathF.Max(0.0f, nextEventDt);
			_timedEvents.Enqueue(new TimedMachineEvent(runtime.Snapshot.MachineId, runtime.TimedEventVersion, absoluteTime), absoluteTime);
		}

		/// <summary>
		/// 计算某台机器距离下一次状态变化还剩多少秒。
		/// </summary>
		private float ComputeNextEventDt(MachineRuntimeState runtime)
		{
			float timeToComplete = ComputeTimeToComplete(runtime);
			float timeToInputDeplete = ComputeTimeToInputDeplete(runtime);
			float timeToOutputFull = ComputeTimeToOutputFull(runtime);
			return MathF.Min(timeToComplete, MathF.Min(timeToInputDeplete, timeToOutputFull));
		}

		/// <summary>
		/// 计算距离当前加工完成还剩多少秒。
		/// </summary>
		private static float ComputeTimeToComplete(MachineRuntimeState runtime)
		{
			if (runtime.Snapshot.State != MachineState.Processing)
			{
				return float.PositiveInfinity;
			}

			float remaining = runtime.Snapshot.Recipe.CycleTime - runtime.Snapshot.ProgressSeconds;
			return MathF.Max(0.0f, remaining);
		}

		/// <summary>
		/// 计算输入耗尽事件时间。
		/// 当前批处理模型在开工时已扣料，因此这里只保留状态表达，不做连续采样。
		/// </summary>
		private static float ComputeTimeToInputDeplete(MachineRuntimeState runtime)
		{
			// 批量生产在开工瞬间扣除输入，因此耗尽只会在 0 时刻转为 InputBlocked。
			return runtime.Snapshot.State == MachineState.InputBlocked ? 0.0f : float.PositiveInfinity;
		}

		/// <summary>
		/// 计算输出写满事件时间。
		/// 当前模型下该事件与加工完成同步发生。
		/// </summary>
		private static float ComputeTimeToOutputFull(MachineRuntimeState runtime)
		{
			// 批量生产在完成瞬间写出输出，输出满载事件与完成事件重合。
			if (runtime.Snapshot.State != MachineState.Processing)
			{
				return float.PositiveInfinity;
			}

			return runtime.Snapshot.Recipe.Outputs.Count == 0
				? float.PositiveInfinity
				: ComputeTimeToComplete(runtime);
		}

		/// <summary>
		/// 尝试将输出缓存区中的物品继续路由到下游。
		/// </summary>
		private void FlushOutputBuffer(MachineRuntimeState runtime)
		{
			if (runtime.Snapshot.OutputBuffer.Count == 0)
			{
				return;
			}

			foreach (string itemId in runtime.Snapshot.OutputBuffer.Keys.ToArray())
			{
				int amount = runtime.Snapshot.OutputBuffer[itemId];
				int residual = RouteToDownstream(runtime, itemId, amount);
				ProductionMath.SetAmount(runtime.Snapshot.OutputBuffer, itemId, residual);
			}
		}

		/// <summary>
		/// 尝试消化因背压留下的待输出结果。
		/// </summary>
		private void FlushPendingOutputs(MachineRuntimeState runtime)
		{
			if (runtime.Snapshot.PendingOutputBuffer.Count == 0)
			{
				return;
			}

			foreach (string itemId in runtime.Snapshot.PendingOutputBuffer.Keys.ToArray())
			{
				int amount = runtime.Snapshot.PendingOutputBuffer[itemId];
				int remainingAfterRoute = RouteToDownstream(runtime, itemId, amount);
				int storedLocally = ProductionMath.AddWithCapacity(runtime.Snapshot.OutputBuffer, runtime.Snapshot.OutputCapacity, itemId, remainingAfterRoute);
				int residual = remainingAfterRoute - storedLocally;
				ProductionMath.SetAmount(runtime.Snapshot.PendingOutputBuffer, itemId, residual);
			}
		}

		/// <summary>
		/// 将一批新产出优先发送到下游，再写入本地输出缓存区，剩余部分进入待输出缓存区。
		/// </summary>
		private void FlushProducedOutputs(MachineRuntimeState runtime, Dictionary<string, int> producedBatch)
		{
			foreach (KeyValuePair<string, int> output in producedBatch.OrderBy(pair => pair.Key, StringComparer.Ordinal))
			{
				int remainingAfterRoute = RouteToDownstream(runtime, output.Key, output.Value);
				int storedLocally = ProductionMath.AddWithCapacity(runtime.Snapshot.OutputBuffer, runtime.Snapshot.OutputCapacity, output.Key, remainingAfterRoute);
				int residual = remainingAfterRoute - storedLocally;
				if (residual > 0)
				{
					int currentPending = ProductionMath.GetAmount(runtime.Snapshot.PendingOutputBuffer, output.Key);
					ProductionMath.SetAmount(runtime.Snapshot.PendingOutputBuffer, output.Key, currentPending + residual);
					runtime.Snapshot.State = MachineState.OutputBlocked;
				}
			}
		}

		/// <summary>
		/// 按优先级将指定物品路由到下游机器，返回未能发送的剩余数量。
		/// </summary>
		private int RouteToDownstream(MachineRuntimeState sourceRuntime, string itemId, int amount)
		{
			int remaining = amount;
			if (remaining <= 0)
			{
				return 0;
			}

			// 路由顺序必须稳定，否则多路分发会影响确定性结果。
			IEnumerable<MachineRoute> routes = sourceRuntime.Snapshot.OutputRoutes
				.Where(route => string.Equals(route.ItemId, itemId, StringComparison.Ordinal))
				.OrderBy(route => route.Priority)
				.ThenBy(route => route.TargetMachineId, StringComparer.Ordinal);

			foreach (MachineRoute route in routes)
			{
				if (!_machines.TryGetValue(route.TargetMachineId, out MachineRuntimeState? targetRuntime))
				{
					continue;
				}

				string targetItemId = string.IsNullOrWhiteSpace(route.TargetInputItemId) ? itemId : route.TargetInputItemId;
				int accepted = ProductionMath.AddWithCapacity(targetRuntime.Snapshot.InputBuffer, targetRuntime.Snapshot.InputCapacity, targetItemId, remaining);
				if (accepted <= 0)
				{
					continue;
				}

				remaining -= accepted;
				EnqueueImmediate(targetRuntime.Snapshot.MachineId);
				if (remaining <= 0)
				{
					break;
				}
			}

			return remaining;
		}

		/// <summary>
		/// 判断机器是否存在任意必需输入不足。
		/// </summary>
		private bool HasAnyInputDeficit(MachineSnapshot snapshot)
		{
			return !ProductionMath.HasRequiredItems(snapshot.InputBuffer, snapshot.Recipe.Inputs);
		}

		/// <summary>
		/// 将机器加入即时处理队列，并利用集合去重避免重复入队。
		/// </summary>
		private void EnqueueImmediate(string machineId)
		{
			if (_immediateSet.Add(machineId))
			{
				_immediateQueue.Enqueue(machineId);
			}
		}

		/// <summary>
		/// 校验一个队列顶部的定时事件是否仍然有效。
		/// </summary>
		private bool IsTimedEventStillValid(TimedMachineEvent timedEvent)
		{
			if (!_machines.TryGetValue(timedEvent.MachineId, out MachineRuntimeState? runtime))
			{
				return false;
			}

			if (runtime.TimedEventVersion != timedEvent.Version)
			{
				return false;
			}

			runtime.SynchronizeProgressTo(ElapsedSeconds);
			return runtime.Snapshot.State == MachineState.Processing;
		}
	}

	/// <summary>
	/// 保存单台机器在本次推演中的运行时附加状态。
	/// </summary>
	private sealed class MachineRuntimeState
	{
		public MachineRuntimeState(MachineSnapshot snapshot)
		{
			Snapshot = snapshot;
			AnchorProgressSeconds = snapshot.ProgressSeconds;
		}

		public MachineSnapshot Snapshot { get; }
		public float AnchorElapsedSeconds { get; set; }
		public float AnchorProgressSeconds { get; set; }
		public int TimedEventVersion { get; set; }

		/// <summary>
		/// 将机器的加工进度同步到指定逻辑时刻。
		/// </summary>
		public void SynchronizeProgressTo(float elapsedSeconds)
		{
			if (Snapshot.State != MachineState.Processing)
			{
				AnchorElapsedSeconds = elapsedSeconds;
				AnchorProgressSeconds = Snapshot.ProgressSeconds;
				return;
			}

			float progressed = AnchorProgressSeconds + MathF.Max(0.0f, elapsedSeconds - AnchorElapsedSeconds);
			Snapshot.ProgressSeconds = MathF.Min(Snapshot.Recipe.CycleTime, progressed);
			AnchorElapsedSeconds = elapsedSeconds;
			AnchorProgressSeconds = Snapshot.ProgressSeconds;
		}
	}

	/// <summary>
	/// 优先队列中的定时事件条目。
	/// </summary>
	private readonly record struct TimedMachineEvent(string MachineId, int Version, float AbsoluteTime);
}
