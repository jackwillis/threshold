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

  test "a reset racing completions leaves no orphan rows", %{world: world, content: content} do
    parallel(8, fn n ->
      if n == 0,
        do: Sessions.reset(world),
        else: Sessions.complete_interaction(world, content, 0, "int:door", "knock")
    end)

    progress = Repo.get_by!(Progress, world: "tiny")
    completed = Repo.aggregate(CompletedInteraction, :count)
    discovered = Repo.aggregate(Discovery, :count)
    assert completed <= 1 and discovered == completed
    assert Repo.all(CompletedInteraction) |> Enum.all?(&(&1.progress_id == progress.id))
  end
end
