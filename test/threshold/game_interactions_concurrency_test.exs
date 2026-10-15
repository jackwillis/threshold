defmodule Threshold.GameInteractionsConcurrencyTest do
  # Independent connections, as in GameSessionsConcurrencyTest: the shared sandbox would hide races.
  # The test database is disposable.
  use ExUnit.Case, async: false

  alias Threshold.{InteractionsFixture, Repo}
  alias Threshold.Game.{CompletedInteraction, Discovery, Progress, Sessions}
  @moduletag :database

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Repo.delete_all(Progress)

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
      Repo.delete_all(Progress)
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    end)

    world = InteractionsFixture.world()
    {:ok, _} = Sessions.load_or_start(world)
    %{world: world, content: InteractionsFixture.content()}
  end

  defp parallel(count, fun) do
    1..count
    |> Task.async_stream(fun, max_concurrency: count, timeout: :infinity)
    |> Enum.map(fn {:ok, result} -> result end)
  end

  test "16 competing completions of one interaction record it exactly once", %{
    world: world,
    content: content
  } do
    results =
      parallel(16, fn n ->
        choice = if rem(n, 2) == 0, do: "knock", else: "listen"
        Sessions.complete_interaction(world, content, 0, "int:door", choice)
      end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :already_completed})) == 15
    assert Repo.aggregate(CompletedInteraction, :count) == 1
    assert Repo.aggregate(Discovery, :count) in [0, 1]

    # The recorded discovery agrees with the one recorded choice.
    %{choice_id: choice} = Repo.one!(CompletedInteraction)
    assert Repo.aggregate(Discovery, :count) == if(choice == "knock", do: 1, else: 0)
  end

  test "a move racing a completion leaves a coherent save", %{world: world, content: content} do
    results =
      parallel(8, fn n ->
        if rem(n, 2) == 0,
          do: {:move, Sessions.move(world, 0, "pn:2")},
          else: {:complete, Sessions.complete_interaction(world, content, 0, "int:door", "knock")}
      end)

    moved = Enum.count(results, &match?({:move, {:ok, _}}, &1))
    completed = Enum.count(results, &match?({:complete, {:ok, _}}, &1))
    assert moved == 1

    # Completion needs the player at loc:a with the turn it was rendered for: it can win only before the move.
    assert completed in [0, 1]
    assert %{turn: 1} = Repo.get_by!(Progress, world: "tiny")
    assert Repo.aggregate(CompletedInteraction, :count) == completed
  end

  test "a reset after competing completions clears the old walk", %{
    world: world,
    content: content
  } do
    parallel(8, fn _ ->
      Sessions.complete_interaction(world, content, 0, "int:door", "knock")
    end)

    assert {:ok, %{turn: 0}} = Sessions.reset(world)
    assert_fresh_walk()
  end

  test "reset waits for a locked completion before clearing its rows", %{
    world: world,
    content: content
  } do
    supervisor = start_supervised!(Task.Supervisor)
    parent = self()

    completion =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Repo.transaction(fn ->
          Repo.query!("SELECT id FROM player_progress FOR UPDATE")
          send(parent, :progress_locked)
          assert_receive :complete, 5_000

          assert {:ok, _} =
                   Sessions.complete_interaction(world, content, 0, "int:door", "knock")
        end)
      end)

    assert_receive :progress_locked, 5_000

    reset =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Repo.checkout(fn ->
          %{rows: [[pid]]} = Repo.query!("SELECT pg_backend_pid()")
          send(parent, {:reset_backend, pid})
          Sessions.reset(world)
        end)
      end)

    assert_receive {:reset_backend, pid}, 5_000
    await_database_lock(pid, System.monotonic_time(:millisecond) + 5_000)
    send(completion.pid, :complete)
    assert {:ok, _} = Task.await(completion)
    assert {:ok, %{turn: 0}} = Task.await(reset)
    assert_fresh_walk()
  end

  defp await_database_lock(pid, deadline) do
    %{rows: [[blocked]]} = Repo.query!("SELECT cardinality(pg_blocking_pids($1)) > 0", [pid])

    unless blocked do
      assert System.monotonic_time(:millisecond) < deadline, "reset never waited on the row lock"
      await_database_lock(pid, deadline)
    end
  end

  defp assert_fresh_walk do
    assert %{turn: 0, location: "pn:1", visited: ["pn:1"]} =
             Repo.get_by!(Progress, world: "tiny")

    assert Repo.aggregate(CompletedInteraction, :count) == 0
    assert Repo.aggregate(Discovery, :count) == 0
  end
end
