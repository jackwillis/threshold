defmodule Threshold.BoundedCache do
  @moduledoc """
  Owns bounded FIFO caches in separate namespaces. Builds run outside the owner;
  concurrent callers of the same cold key share one monitored build. Failed builds
  are returned to all waiters and never cached. Entries live in ETS, avoiding
  persistent-term global collection during insertion and eviction.
  """
  use GenServer

  @keep 4

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def fetch(namespace, key, build) do
    case GenServer.call(__MODULE__, {:fetch, namespace, key, build}, :infinity) do
      {:raised, kind, reason, stack} -> :erlang.raise(kind, reason, stack)
      result -> result
    end
  end

  def clear(namespace), do: invalidate(namespace, fn _ -> true end)

  def invalidate(namespace, predicate),
    do: GenServer.call(__MODULE__, {:invalidate, namespace, predicate})

  @doc false
  def entries(namespace), do: GenServer.call(__MODULE__, {:entries, namespace})

  @impl true
  def init(_) do
    table = :ets.new(__MODULE__, [:set, :private])
    {:ok, %{table: table, recent: %{}, pending: %{}, epochs: %{}}}
  end

  @impl true
  def handle_call({:fetch, namespace, key, build}, from, state) do
    full = {namespace, key}
    epoch = Map.get(state.epochs, namespace, 0)
    flight = {full, epoch}

    case :ets.lookup(state.table, full) do
      [{^full, value}] ->
        {:reply, {:ok, value}, state}

      [] ->
        case state.pending do
          %{^flight => pending} ->
            pending = %{pending | waiters: [from | pending.waiters]}
            {:noreply, put_in(state.pending[flight], pending)}

          _ ->
            owner = self()

            {pid, ref} =
              spawn_monitor(fn ->
                result =
                  try do
                    build.()
                  catch
                    kind, reason -> {:raised, kind, reason, __STACKTRACE__}
                  end

                send(owner, {:built, self(), flight, result})
              end)

            pending = %{pid: pid, ref: ref, waiters: [from]}
            {:noreply, put_in(state.pending[flight], pending)}
        end
    end
  end

  def handle_call({:entries, namespace}, _from, state) do
    {:reply, :ets.match_object(state.table, {{namespace, :_}, :_}), state}
  end

  def handle_call({:invalidate, namespace, predicate}, _from, state) do
    recent = Map.get(state.recent, namespace, [])
    {drop, keep} = Enum.split_with(recent, predicate)
    for key <- drop, do: :ets.delete(state.table, {namespace, key})

    {:reply, :ok,
     %{
       state
       | recent: Map.put(state.recent, namespace, keep),
         epochs: Map.update(state.epochs, namespace, 1, &(&1 + 1))
     }}
  end

  @impl true
  def handle_info({:built, pid, {{namespace, key} = full, epoch} = flight, result}, state) do
    %{pid: ^pid} = pending = Map.fetch!(state.pending, flight)
    Process.demonitor(pending.ref, [:flush])

    reply =
      case result do
        {:uncached, value} -> {:ok, value}
        other -> other
      end

    Enum.each(pending.waiters, &GenServer.reply(&1, reply))
    state = %{state | pending: Map.delete(state.pending, flight)}
    current_epoch = Map.get(state.epochs, namespace, 0)

    state =
      case result do
        {:ok, value} when epoch == current_epoch ->
          recent = [key | List.delete(Map.get(state.recent, namespace, []), key)]
          {keep, drop} = Enum.split(recent, @keep)
          :ets.insert(state.table, {full, value})
          for old <- drop, do: :ets.delete(state.table, {namespace, old})
          %{state | recent: Map.put(state.recent, namespace, keep)}

        _ ->
          state
      end

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Enum.find(state.pending, fn {_, pending} -> pending.ref == ref end) do
      {full, pending} ->
        Enum.each(pending.waiters, &GenServer.reply(&1, {:raised, :exit, reason, []}))
        {:noreply, %{state | pending: Map.delete(state.pending, full)}}

      nil ->
        {:noreply, state}
    end
  end
end
