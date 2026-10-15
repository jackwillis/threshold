defmodule Threshold.BoundedCacheTest do
  use ExUnit.Case, async: false

  alias Threshold.BoundedCache

  setup do
    BoundedCache.clear(:cache_test)
    :ok
  end

  test "cold waiters share a build, including a cached nil" do
    parent = self()
    counter = start_supervised!({Agent, fn -> 0 end})

    build = fn ->
      Agent.update(counter, &(&1 + 1))
      send(parent, {:building, self()})

      receive do
        :finish -> {:ok, nil}
      end
    end

    first = Task.async(fn -> BoundedCache.fetch(:cache_test, :same, build) end)
    assert_receive {:building, builder}

    others =
      for _ <- 1..15, do: Task.async(fn -> BoundedCache.fetch(:cache_test, :same, build) end)

    send(builder, :finish)
    assert Task.await(first) == {:ok, nil}
    for task <- others, do: assert(Task.await(task) == {:ok, nil})
    assert Agent.get(counter, & &1) == 1
  end

  test "failed builds are retried and exceptions do not crash the owner" do
    assert {:error, :bad} = BoundedCache.fetch(:cache_test, :failure, fn -> {:error, :bad} end)
    assert {:ok, :good} = BoundedCache.fetch(:cache_test, :failure, fn -> {:ok, :good} end)

    assert_raise RuntimeError, "broken", fn ->
      BoundedCache.fetch(:cache_test, :exception, fn -> raise "broken" end)
    end

    assert {:ok, :recovered} =
             BoundedCache.fetch(:cache_test, :exception, fn -> {:ok, :recovered} end)
  end

  test "clear during a build prevents stale insertion" do
    parent = self()

    task =
      Task.async(fn ->
        BoundedCache.fetch(:cache_test, :cleared, fn ->
          send(parent, {:building, self()})

          receive do
            :finish -> {:ok, :old}
          end
        end)
      end)

    assert_receive {:building, builder}
    assert :ok = BoundedCache.clear(:cache_test)
    assert {:ok, :fresh} = BoundedCache.fetch(:cache_test, :cleared, fn -> {:ok, :fresh} end)
    send(builder, :finish)
    assert Task.await(task) == {:ok, :old}
    assert [{{:cache_test, :cleared}, :fresh}] = BoundedCache.entries(:cache_test)
  end

  test "a killed builder releases its waiters and permits retry" do
    parent = self()

    task =
      Task.async(fn ->
        catch_exit(
          BoundedCache.fetch(:cache_test, :killed, fn ->
            send(parent, {:building, self()})

            receive do
              :never -> {:ok, :never}
            end
          end)
        )
      end)

    assert_receive {:building, builder}
    Process.exit(builder, :kill)
    assert Task.await(task) == :killed
    assert {:ok, :retry} = BoundedCache.fetch(:cache_test, :killed, fn -> {:ok, :retry} end)
  end
end
