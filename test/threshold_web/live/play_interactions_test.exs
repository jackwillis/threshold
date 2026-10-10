defmodule ThresholdWeb.PlayInteractionsTest do
  use ThresholdWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Threshold.{Authored, Repo}
  alias Threshold.Game.{CompletedInteraction, Discovery, Progress}
  @moduletag :database
  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    File.cp_r!(Path.join(Threshold.World.root(), "tiny"), Path.join(tmp, "tiny"))
    previous = Application.get_env(:threshold, :worlds_dir)
    Application.put_env(:threshold, :worlds_dir, tmp)
    on_exit(fn -> Application.put_env(:threshold, :worlds_dir, previous) end)

    place = fn id, anchor, extra ->
      Map.merge(%{"id" => id, "name" => "New location", "anchor" => anchor}, extra)
    end

    node = fn ref, point -> %{"kind" => "node", "ref" => ref, "point" => point} end

    authored =
      Map.merge(Authored.empty(), %{
        "spawns" => [%{"id" => "spawn:default", "location" => "pn:1", "default" => true}],
        "locations" => [
          place.("loc:a", node.("node:1", [-89.385, 43.074]), %{
            "name" => "The corner",
            "notes" => "Quiet."
          }),
          place.(
            "loc:b",
            %{
              "kind" => "edge",
              "ref" => "edge:1-2-101",
              "offset" => 0.5,
              "point" => [-89.3825, 43.0745],
              "ref_geometry_hash" => "deadbeef"
            },
            %{}
          ),
          place.("loc:c", node.("node:2", [-89.38, 43.075]), %{})
        ],
        "connections" => [
          %{
            "id" => "conn:ab",
            "from" => "loc:a",
            "to" => "loc:b",
            "kind" => "fictional",
            "geometry" => nil
          },
          %{
            "id" => "conn:bc",
            "from" => "loc:b",
            "to" => "loc:c",
            "kind" => "fictional",
            "geometry" => nil
          }
        ]
      })

    File.write!(Path.join([tmp, "tiny", "authored.json"]), Authored.encode(authored))

    File.cp!(
      Path.expand("../../fixtures/interactions/synthetic.json", __DIR__),
      Path.join([tmp, "tiny", "interactions.json"])
    )

    %{dir: Path.join(tmp, "tiny")}
  end

  defp rows, do: {Repo.aggregate(Discovery, :count), Repo.aggregate(CompletedInteraction, :count)}

  test "arrival only indicates that something can be investigated; nothing opens or is written",
       %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/play")
    assert has_element?(view, "#interaction-outcome", "Something here can be investigated")
    assert has_element?(view, "#investigate-0", "Unmarked door")
    refute has_element?(view, "#scene")
    assert {0, 0} = rows()
  end

  test "opening and closing a scene is transient and writes nothing", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/play")
    view |> element("#investigate-0") |> render_click()
    assert has_element?(view, "#scene #scene-title", "A faint tapping")
    assert has_element?(view, "#scene", "Evenly spaced")
    assert has_element?(view, "#choice-0", "Knock back")
    assert {0, 0} = rows()

    view |> element("#close-scene") |> render_click()
    refute has_element?(view, "#scene")
    assert {0, 0} = rows()
    assert %{turn: 0} = Repo.get_by!(Progress, world: "tiny:authored")
  end

  test "choosing records the completion and its discovery for free, and unlocks the second place",
       %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/play")
    view |> element("#investigate-0") |> render_click()
    view |> element("#choice-0") |> render_click()

    assert has_element?(view, "#interaction-outcome", "Recorded: The tapping is a signal")
    refute has_element?(view, "#scene")
    assert has_element?(view, "#investigated-0", "Unmarked door")
    assert has_element?(view, "#player-turn", "0")
    assert {1, 1} = rows()

    view |> element("#walk-0") |> render_click()
    assert has_element?(view, "#player-turn", "1")
    assert has_element?(view, "#investigate-0", "Dead streetlamp")
  end

  test "the other choice does not unlock the second place", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/play")
    view |> element("#investigate-0") |> render_click()
    view |> element("#choice-1") |> render_click()
    assert has_element?(view, "#interaction-outcome", "Recorded.")
    view |> element("#walk-0") |> render_click()
    refute has_element?(view, "#interactions", "Dead streetlamp")
  end

  test "an open scene does not block movement, and walking away closes it", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/play")
    view |> element("#investigate-0") |> render_click()
    assert has_element?(view, "#scene")
    view |> element("#walk-0") |> render_click()
    assert has_element?(view, "#player-turn", "1")
    refute has_element?(view, "#scene")
    assert {0, 0} = rows()
  end

  test "a forged completion for a hidden interaction is refused and writes nothing", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/play")

    render_hook(view, "complete_interaction", %{
      "id" => "int:lamp",
      "choice" => "note",
      "turn" => "0"
    })

    assert has_element?(view, "#interaction-outcome", "no longer available")
    assert {0, 0} = rows()

    render_hook(view, "open_interaction", %{"id" => "int:lamp"})
    refute has_element?(view, "#scene")
  end

  test "a completion from a stale turn is refused", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/play")
    view |> element("#walk-0") |> render_click()

    render_hook(view, "complete_interaction", %{
      "id" => "int:door",
      "choice" => "knock",
      "turn" => "0"
    })

    assert {0, 0} = rows()
  end

  test "completions survive a reload, and a new walk discards them", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/play")
    view |> element("#investigate-0") |> render_click()
    view |> element("#choice-0") |> render_click()

    {:ok, again, _} = live(conn, ~p"/play")
    assert has_element?(again, "#investigated-0", "Unmarked door")
    refute has_element?(again, "#investigate-0")

    again |> element("#new-walk") |> render_click()
    assert {0, 0} = rows()
    assert has_element?(again, "#investigate-0", "Unmarked door")
  end

  test "a place with no interactions shows no investigate section", %{conn: conn, dir: dir} do
    File.rm!(Path.join(dir, "interactions.json"))
    {:ok, view, _} = live(conn, ~p"/play")
    refute has_element?(view, "#interactions")
    assert has_element?(view, "#player-turn", "0")
  end

  test "an invalid interactions file is reported without breaking the walk", %{
    conn: conn,
    dir: dir
  } do
    File.write!(Path.join(dir, "interactions.json"), "{}")
    {:ok, view, _} = live(conn, ~p"/play")
    assert has_element?(view, "#interaction-note", "unavailable")
    view |> element("#walk-0") |> render_click()
    assert has_element?(view, "#player-turn", "1")
  end

  describe "accessibility" do
    test "a persistent live region exists from the first render and announces arrival", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/play")

      assert has_element?(
               view,
               "#interaction-live[role=status][aria-live=polite]",
               "Something here can be investigated: Unmarked door."
             )
    end

    test "the live region exists even where there is nothing to investigate", %{
      conn: conn,
      dir: dir
    } do
      File.rm!(Path.join(dir, "interactions.json"))
      {:ok, view, _} = live(conn, ~p"/play")
      assert has_element?(view, "#interaction-live[role=status]")
      assert view |> element("#interaction-live") |> render() =~ ~r/>\s*<\/div>/
    end

    test "the live region announces the recorded outcome, then the visible text carries focus", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/play")
      view |> element("#investigate-0") |> render_click()
      view |> element("#choice-0") |> render_click()

      assert has_element?(view, "#interaction-live", "Recorded: The tapping is a signal.")
      # A fresh element per outcome so phx-mounted moves focus to it every time.
      assert has_element?(view, "#outcome-1[tabindex='-1'][phx-mounted]")
      refute has_element?(view, "#interaction-outcome[role]")
    end

    test "refusals are announced too, with a new focus target", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play")

      render_hook(view, "complete_interaction", %{
        "id" => "int:lamp",
        "choice" => "note",
        "turn" => "0"
      })

      assert has_element?(view, "#interaction-live", "That is no longer available here.")
      assert has_element?(view, "#outcome-1[tabindex='-1']")

      render_hook(view, "complete_interaction", %{
        "id" => "int:lamp",
        "choice" => "note",
        "turn" => "0"
      })

      assert has_element?(view, "#outcome-2[tabindex='-1']")
      refute has_element?(view, "#outcome-1")
    end

    test "the investigate button is a disclosure, and the scene title takes focus when it opens",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play")
      assert has_element?(view, "#investigate-0[aria-expanded=false][aria-controls=scene]")

      view |> element("#investigate-0") |> render_click()
      assert has_element?(view, "#investigate-0[aria-expanded=true]", "Close")
      assert has_element?(view, "#scene[aria-labelledby=scene-title]")
      assert has_element?(view, "#scene-title[tabindex='-1'][phx-mounted]")

      # The same button closes it again, and the live region says nothing while a scene is open.
      assert view |> element("#interaction-live") |> render() =~ ~r/>\s*<\/div>/
      view |> element("#investigate-0") |> render_click()
      refute has_element?(view, "#scene")
      assert has_element?(view, "#investigate-0[aria-expanded=false]")
    end

    test "closing returns focus to the investigate button, by button or by Escape", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play")
      view |> element("#investigate-0") |> render_click()

      close = view |> element("#close-scene") |> render()
      assert close =~ "#investigate-0" and close =~ "close_interaction"

      scene = view |> element("#scene") |> render()
      assert scene =~ ~s(phx-key="Escape")
      assert scene =~ "#investigate-0"

      view |> element("#close-scene") |> render_click()
      refute has_element?(view, "#scene")
    end

    test "choice buttons are real buttons and the scene is a labelled region, not a dialog", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/play")
      view |> element("#investigate-0") |> render_click()
      assert has_element?(view, "#scene button#choice-0")
      refute has_element?(view, "#scene[role=dialog], #scene[aria-modal]")
    end

    test "walking away from an open scene asks the client to restore focus to a stable heading",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play")
      assert has_element?(view, "h2#next-step-heading[tabindex='-1']", "Your next step")

      view |> element("#investigate-0") |> render_click()
      view |> element("#walk-0") |> render_click()
      assert_push_event(view, "restore-focus", %{to: "#next-step-heading"})
      refute has_element?(view, "#scene")
    end

    test "no focus event is sent when no scene was open", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play")
      view |> element("#walk-0") |> render_click()
      refute_push_event(view, "restore-focus", _)
    end
  end
end
