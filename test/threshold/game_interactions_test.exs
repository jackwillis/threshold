defmodule Threshold.GameInteractionsTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  alias Threshold.{InteractionsFixture, Repo}
  alias Threshold.Game.{CompletedInteraction, Discovery, Progress, Sessions}
  @moduletag :database

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    world = InteractionsFixture.world()
    {:ok, _player} = Sessions.load_or_start(world)
    %{world: world, content: InteractionsFixture.content()}
  end

  defp rows, do: {Repo.aggregate(Discovery, :count), Repo.aggregate(CompletedInteraction, :count)}

  defp complete(world, content, turn, interaction, choice),
    do: Sessions.complete_interaction(world, content, turn, interaction, choice)

  test "completing records the choice and its discoveries and spends no turn", %{
    world: world,
    content: content
  } do
    assert {:ok, %{completed: completed, discovered: ["disc:tapping"]}} =
             complete(world, content, 0, "int:door", "knock")

    assert %{interaction_id: "int:door", choice_id: "knock", turn: 0} = completed
    assert %{turn: 0} = Repo.get_by!(Progress, world: "tiny")

    assert {:ok, %{discovered: discovered, completed: done}} = Sessions.interaction_state(world)
    assert discovered == MapSet.new(["disc:tapping"])
    assert done == MapSet.new(["int:door"])
    assert %{source_interaction_id: "int:door"} = Repo.one!(Discovery)
  end

  test "a choice without discoveries still completes", %{world: world, content: content} do
    assert {:ok, %{discovered: []}} = complete(world, content, 0, "int:door", "listen")
    assert {0, 1} = rows()
  end

  test "a replay is refused and writes nothing", %{world: world, content: content} do
    assert {:ok, _} = complete(world, content, 0, "int:door", "knock")
    assert {:error, :already_completed} = complete(world, content, 0, "int:door", "knock")
    assert {:error, :already_completed} = complete(world, content, 0, "int:door", "listen")
    assert {1, 1} = rows()
  end

  test "a hidden interaction cannot be completed by a forged request", %{
    world: world,
    content: content
  } do
    # int:lamp needs disc:tapping, and the player is not at loc:b: both stop it.
    assert {:error, :unavailable} = complete(world, content, 0, "int:lamp", "note")
    {:ok, {_moved, _}} = Sessions.move(world, 0, "pn:2")
    assert {:error, :unavailable} = complete(world, content, 1, "int:lamp", "note")
    assert {0, 0} = rows()
  end

  test "A then B: the discovery makes the second interaction available", %{
    world: world,
    content: content
  } do
    assert {:ok, _} = complete(world, content, 0, "int:door", "knock")
    assert {:ok, {_, _}} = Sessions.move(world, 0, "pn:2")

    assert {:ok, %{completed: %{interaction_id: "int:lamp", turn: 1}}} =
             complete(world, content, 1, "int:lamp", "note")

    assert {1, 2} = rows()
  end

  test "choosing 'listen' does not unlock the second interaction", %{
    world: world,
    content: content
  } do
    assert {:ok, _} = complete(world, content, 0, "int:door", "listen")
    {:ok, {_, _}} = Sessions.move(world, 0, "pn:2")
    assert {:error, :unavailable} = complete(world, content, 1, "int:lamp", "note")
  end

  test "the wrong place, a stale turn and an unknown choice or interaction write nothing", %{
    world: world,
    content: content
  } do
    {:ok, {_, _}} = Sessions.move(world, 0, "pn:2")
    assert {:error, :unavailable} = complete(world, content, 1, "int:door", "knock")
    assert {:error, :stale_turn} = complete(world, content, 0, "int:door", "knock")
    assert {:error, :unavailable} = complete(world, content, 1, "int:nope", "knock")
    {:ok, {_, _}} = Sessions.move(world, 1, "pn:1")
    assert {:error, :unknown_choice} = complete(world, content, 2, "int:door", "dance")
    assert {:error, :unknown_choice} = complete(world, content, 2, "int:door", "note")
    assert {0, 0} = rows()
  end

  test "moving writes no interaction rows, and walking back and forth changes nothing", %{
    world: world,
    content: content
  } do
    {:ok, {_, _}} = Sessions.move(world, 0, "pn:2")
    {:ok, {_, _}} = Sessions.move(world, 1, "pn:1")
    assert {0, 0} = rows()
    assert {:ok, _} = complete(world, content, 2, "int:door", "knock")
  end

  test "a changed world revision blocks completion", %{world: world, content: content} do
    changed = %{world | revision: "other"}
    assert {:error, message} = complete(changed, content, 0, "int:door", "knock")
    assert message =~ "world has changed"
    assert {0, 0} = rows()
  end

  test "no save means no completion", %{content: content} do
    Repo.delete_all(Progress)

    assert {:error, :missing_save} =
             complete(InteractionsFixture.world(), content, 0, "int:door", "knock")
  end

  test "a new walk discards discoveries and completed interactions", %{
    world: world,
    content: content
  } do
    assert {:ok, _} = complete(world, content, 0, "int:door", "knock")
    assert {1, 1} = rows()
    assert {:ok, _player} = Sessions.reset(world)
    assert {0, 0} = rows()
    assert {:ok, %{discovered: d, completed: c}} = Sessions.interaction_state(world)
    assert MapSet.size(d) == 0 and MapSet.size(c) == 0
    assert {:ok, _} = complete(world, content, 0, "int:door", "listen")
  end

  test "a forced new walk after a revision change also clears them", %{
    world: world,
    content: content
  } do
    assert {:ok, _} = complete(world, content, 0, "int:door", "knock")
    changed = %{world | revision: "other"}
    assert {:ok, _} = Sessions.reset(changed)
    assert {0, 0} = rows()
  end

  test "removing content leaves saved rows harmless", %{world: world, content: content} do
    assert {:ok, _} = complete(world, content, 0, "int:door", "knock")
    trimmed = %{content | "interactions" => [], "discoveries" => []}
    assert {:ok, %{discovered: d}} = Sessions.interaction_state(world)
    assert d == MapSet.new(["disc:tapping"])
    assert {:error, :unavailable} = complete(world, trimmed, 0, "int:door", "knock")
    assert {1, 1} = rows()
  end

  test "progress rows are per session: another world's discoveries are separate", %{
    world: world,
    content: content
  } do
    assert {:ok, _} = complete(world, content, 0, "int:door", "knock")
    other = %{world | name: "elsewhere"}
    assert {:ok, _} = Sessions.load_or_start(other)
    assert {:ok, %{discovered: d}} = Sessions.interaction_state(other)
    assert MapSet.size(d) == 0
    assert Repo.one(from(d in Discovery, select: count(d.id))) == 1
  end

  test "the unique indexes backstop the application checks", %{world: world, content: content} do
    assert {:ok, %{completed: %{progress_id: id}}} =
             complete(world, content, 0, "int:door", "knock")

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%CompletedInteraction{
        progress_id: id,
        interaction_id: "int:door",
        choice_id: "x",
        turn: 0
      })
    end
  end
end
