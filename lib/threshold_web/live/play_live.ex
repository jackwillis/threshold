defmodule ThresholdWeb.PlayLive do
  use ThresholdWeb, :live_view
  alias Threshold.{Game, Interactions}
  alias Threshold.Game.{Geometry, Sessions, World}

  @impl true
  def mount(params, _session, socket) do
    name = params["world"] || Application.get_env(:threshold, :default_world, "madison")

    graph =
      case params["graph"] || Application.get_env(:threshold, :play_graph, "authored") do
        value when value in [:authored, "authored"] -> :authored
        _ -> :generated
      end

    socket =
      assign(socket,
        page_title: "Explore",
        world_name: name,
        graph: graph,
        world: nil,
        player: nil,
        error: nil,
        map_error: nil,
        moves: [],
        nearby: [],
        inspected: nil,
        movement: nil,
        interactions: [],
        interaction_note: nil,
        open_interaction: nil,
        outcome: nil,
        camera: 0,
        map_state: "{}"
      )

    {:ok, load(socket)}
  end

  @impl true
  def handle_event("move", params, socket) do
    expected =
      case params["turn"] do
        n when is_integer(n) ->
          n

        n when is_binary(n) ->
          case Integer.parse(n) do
            {value, ""} -> value
            _ -> nil
          end

        _ ->
          nil
      end

    with true <- socket.assigns.player != nil,
         {:ok, world} <- World.load(socket.assigns.world_name, graph: socket.assigns.graph),
         {:ok, {player, route}} <- Sessions.move(world, expected, params["destination"]) do
      {:noreply,
       present(
         assign(socket,
           world: world,
           player: player,
           error: nil,
           inspected: nil,
           open_interaction: nil,
           outcome: nil,
           movement: %{turn: player.turn, geometry: route.geometry}
         )
       )}
    else
      {:error, :stale_turn} ->
        {:noreply,
         load(socket) |> put_flash(:error, "Your walk was updated. Choose your next step again.")}

      {:error, :unavailable} ->
        {:noreply, put_flash(socket, :error, "That step is unavailable.")}

      {:error, message} when is_binary(message) ->
        {:noreply, assign(socket, error: message)}

      _ ->
        {:noreply, put_flash(socket, :error, "Unable to take that step.")}
    end
  end

  def handle_event("inspect", %{"id" => id}, socket) do
    place = Enum.find(socket.assigns.nearby, &(&1["id"] == id))
    {:noreply, assign(socket, inspected: place)}
  end

  def handle_event("close_inspect", _, socket), do: {:noreply, assign(socket, inspected: nil)}

  # Opening and closing a scene is transient presentation: nothing is written until a choice is
  # completed, and the server re-validates everything then.
  def handle_event("open_interaction", %{"id" => id}, socket) do
    available? =
      Enum.any?(
        socket.assigns.interactions,
        &(&1.status == :available and &1.interaction["id"] == id)
      )

    {:noreply, assign(socket, open_interaction: if(available?, do: id), outcome: nil)}
  end

  def handle_event("close_interaction", _, socket),
    do: {:noreply, assign(socket, open_interaction: nil)}

  def handle_event("complete_interaction", %{"id" => id, "choice" => choice} = params, socket) do
    with turn when is_integer(turn) <- parse_turn(params["turn"]),
         true <- socket.assigns.player != nil,
         {:ok, world} <- World.load(socket.assigns.world_name, graph: socket.assigns.graph),
         {:ok, content} <- load_interactions(socket.assigns.world_name),
         {:ok, %{discovered: discovered}} <-
           Sessions.complete_interaction(world, content, turn, id, choice) do
      labels = for d <- content["discoveries"], d["id"] in discovered, do: d["label"]

      {:noreply,
       present(assign(socket, world: world, open_interaction: nil, outcome: {:recorded, labels}))}
    else
      {:error, :stale_turn} ->
        {:noreply, load(socket) |> put_flash(:error, "Your walk was updated. Look around again.")}

      {:error, reason} when reason in [:unavailable, :already_completed, :unknown_choice] ->
        {:noreply,
         socket
         |> assign(open_interaction: nil, outcome: {:refused, reason})
         |> present()}

      {:error, message} when is_binary(message) ->
        {:noreply, assign(socket, error: message)}

      _ ->
        {:noreply, put_flash(socket, :error, "Unable to record that.")}
    end
  end

  def handle_event("recenter", _, socket),
    do: {:noreply, present(update(socket, :camera, &(&1 + 1)))}

  def handle_event("new_walk", _, socket) do
    with {:ok, world} <- World.load(socket.assigns.world_name, graph: socket.assigns.graph),
         true <- Sessions.enabled?(),
         {:ok, player} <- Sessions.reset(world) do
      {:noreply,
       present(
         assign(socket,
           world: world,
           player: player,
           error: nil,
           inspected: nil,
           open_interaction: nil,
           outcome: nil,
           movement: nil,
           camera: socket.assigns.camera + 1
         )
       )}
    else
      {:error, message} when is_binary(message) -> {:noreply, assign(socket, error: message)}
      _ -> {:noreply, assign(socket, error: "Player saves are not configured.")}
    end
  end

  def handle_event("map_failed", %{"message" => message}, socket),
    do: {:noreply, assign(socket, map_error: message)}

  defp load(socket) do
    with {:ok, world} <- World.load(socket.assigns.world_name, graph: socket.assigns.graph),
         {:ok, player} <- Sessions.load_or_start(world) do
      present(
        assign(socket, world: world, player: player, error: nil, movement: nil, inspected: nil)
      )
    else
      {:error, message} -> assign(socket, error: message)
    end
  end

  defp parse_turn(n) when is_integer(n), do: n

  defp parse_turn(n) when is_binary(n) do
    case Integer.parse(n) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp parse_turn(_), do: nil

  # The interactions file is small and parsed per event (see docs/gameplay-interactions.md). A
  # missing file is simply no interactions; an invalid one is reported in the panel, not a crash.
  defp load_interactions(world_name) do
    with {:ok, dir} <- Threshold.World.dir(world_name),
         {:ok, content, _hash} <- Interactions.load(dir) do
      {:ok, content}
    else
      {:error, errors} when is_list(errors) -> {:error, Enum.join(errors, " ")}
      _ -> {:error, "World not found."}
    end
  end

  # What can be investigated here. Presentation only: the server re-checks on completion.
  defp refresh_interactions(socket) do
    %{world: world, player: player} = socket.assigns

    # A world with no interactions never touches the interaction tables, so it keeps working
    # before the migration has been applied.
    with true <- Sessions.enabled?(),
         {:ok, %{"interactions" => [_ | _]} = content} <-
           load_interactions(socket.assigns.world_name),
         {:ok, state} <- Sessions.interaction_state(world) do
      list = Interactions.at(content, world, player, state)

      open =
        if Enum.any?(
             list,
             &(&1.status == :available and &1.interaction["id"] == socket.assigns.open_interaction)
           ),
           do: socket.assigns.open_interaction

      assign(socket, interactions: list, open_interaction: open, interaction_note: nil)
    else
      {:error, message} when is_binary(message) ->
        assign(socket, interactions: [], open_interaction: nil, interaction_note: message)

      _ ->
        assign(socket, interactions: [], open_interaction: nil, interaction_note: nil)
    end
  end

  defp present(%{assigns: %{player: nil}} = socket), do: socket

  defp present(socket) do
    socket = refresh_interactions(socket)
    %{world: world, player: player} = socket.assigns
    point = world.locations[player.location]["point"]
    moves = Game.numbered_moves(world, player)
    spawn = Enum.find(world.spawns, & &1["default"])

    state = %{
      point: point,
      turn: player.turn,
      moves: moves,
      visited:
        for(
          id <- player.visited,
          Map.has_key?(world.locations, id),
          do: world.locations[id]["point"]
        ),
      movement: socket.assigns.movement,
      camera: socket.assigns.camera,
      zoom: spawn["zoom"] || 18.5,
      bounds: bounds(world.boundary),
      limits: camera_limits()
    }

    assign(socket,
      moves: moves,
      nearby: Game.nearby(world, player),
      map_state: Jason.encode!(state)
    )
  end

  # West, south, east, north of the playable boundary, for the camera's coarse world limit.
  defp bounds(%{"coordinates" => rings}) do
    points = List.flatten(rings) |> Enum.chunk_every(2)
    {lons, lats} = {Enum.map(points, &Enum.at(&1, 0)), Enum.map(points, &Enum.at(&1, 1))}
    [Enum.min(lons), Enum.min(lats), Enum.max(lons), Enum.max(lats)]
  end

  defp bounds(_), do: nil

  # Optional overrides of the Field Atlas camera limits, e.g.
  # `config :threshold, :atlas_camera, min_zoom: 17, max_zoom: 19.5, max_displacement_m: 200`.
  defp camera_limits do
    config = Application.get_env(:threshold, :atlas_camera, [])

    for {key, name} <- [
          min_zoom: "minZoom",
          max_zoom: "maxZoom",
          max_displacement_m: "maxDisplacementM"
        ],
        value = config[key],
        into: %{},
        do: {name, value}
  end

  defp direction(from, to) do
    Enum.at(
      ~w(north northeast east southeast south southwest west northwest),
      rem(round(Geometry.bearing(from, to) / 45), 8)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} mode="play">
      <div class="play-layout">
        <div
          :if={@player}
          id="player-map"
          phx-hook="PlayerMap"
          data-world={@world_name}
          data-snapshot={@world.generation}
          data-state={@map_state}
        >
          <div id="player-map-canvas" phx-update="ignore"></div>
          <%!-- Ignored by LiveView patches so the season variables and button state set by the hook persist. --%>
          <div id="play-chrome" phx-update="ignore">
            <div class="play-map-label">Madison <span>One step at a time</span></div>
            <div
              id="play-seasons"
              class="atlas-seasons play-seasons"
              role="group"
              aria-label="Map season (appearance only)"
            >
              <button
                :for={season <- ~w(spring summer autumn winter)}
                type="button"
                data-season={season}
                aria-pressed="false"
              >
                {season}
              </button>
            </div>
          </div>
          <button id="recenter-player" class="play-recenter" phx-click="recenter">Recenter</button>
          <p :if={@map_error} id="player-map-error" class="map-status map-status-error">
            {@map_error}
          </p>
        </div>
        <aside id="player-panel" class="play-panel">
          <p class="play-eyebrow">Threshold · exploration</p>
          <h1>Walk the city</h1>
          <p :if={@error} id="play-error" role="alert">{@error}</p>
          <%= if @player do %>
            <div id="player-progress" class="play-progress" aria-live="polite">
              <span>Turn <strong id="player-turn">{@player.turn}</strong></span>
              <span><strong id="player-visited">{MapSet.size(@player.visited)}</strong> places visited</span>
            </div>
            <p :if={@graph == :authored} id="graph-note" class="play-hint">
              Authored map: every stop is a place from the world editor.
            </p>
            <details :if={@world.warnings != []} id="map-notes" class="play-hint play-warning">
              <summary>Map notes ({length(@world.warnings)})</summary>
              <p :for={warning <- @world.warnings}>{warning}</p>
            </details>
            <h2>Your next step</h2>
            <p class="play-hint">
              Choose a glowing marker or a direction below, or press its number key. Numbers run clockwise from north.
            </p>
            <div id="available-moves" class="play-moves">
              <button
                :for={{move, index} <- Enum.with_index(@moves)}
                id={"walk-#{index}"}
                phx-click="move"
                phx-value-destination={move.destination}
                phx-value-turn={@player.turn}
                aria-keyshortcuts={move.key}
              >
                <span>
                  <kbd :if={move.key} class="play-key" aria-hidden="true">{move.key}</kbd>
                  Walk {direction(@world.locations[@player.location]["point"], move.point)}
                </span>
                <small>{round(move.length_m)} m <.icon name="hero-arrow-right" class="w-4 h-4" /></small>
              </button>
            </div>
            <p :if={@moves == []} class="play-hint">No walkable routes from here.</p>
            <h2>Nearby</h2>
            <p :if={@nearby == []} class="play-hint">Nothing to inspect at this corner.</p>
            <button
              :for={{place, index} <- Enum.with_index(@nearby)}
              id={"inspect-#{index}"}
              class="play-place"
              phx-click="inspect"
              phx-value-id={place["id"]}
            >
              <span>{place["name"]}</span><small>Inspect</small>
            </button>
            <section
              :if={@interactions != [] or @outcome != nil or @interaction_note != nil}
              id="interactions"
              aria-labelledby="interactions-heading"
            >
              <h2 id="interactions-heading">Investigate</h2>
              <p :if={@interaction_note} id="interaction-note" class="play-hint play-warning">
                Investigations are unavailable: {@interaction_note}
              </p>
              <p id="interaction-outcome" class="play-hint" role="status">
                <%= case @outcome do %>
                  <% {:recorded, []} -> %>
                    Recorded.
                  <% {:recorded, labels} -> %>
                    Recorded: {Enum.join(labels, "; ")}.
                  <% {:refused, _} -> %>
                    That is no longer available here.
                  <% _ -> %>
                    <%= if Enum.any?(@interactions, &(&1.status == :available)) and @open_interaction == nil do %>
                      Something here can be investigated.
                    <% end %>
                <% end %>
              </p>
              <%= for {entry, index} <- Enum.with_index(@interactions) do %>
                <button
                  :if={entry.status == :available and @open_interaction != entry.interaction["id"]}
                  id={"investigate-#{index}"}
                  class="play-place"
                  phx-click="open_interaction"
                  phx-value-id={entry.interaction["id"]}
                >
                  <span>{entry.interaction["title"]}</span><small>Investigate</small>
                </button>
                <p :if={entry.status == :completed} id={"investigated-#{index}"} class="play-hint">
                  Investigated: {entry.interaction["title"]}
                </p>
                <section
                  :if={@open_interaction == entry.interaction["id"]}
                  id="scene"
                  class="play-inspection play-scene"
                  aria-labelledby="scene-title"
                >
                  <h3 id="scene-title">{entry.interaction["scene"]["title"]}</h3>
                  <p :for={paragraph <- entry.interaction["scene"]["body"]}>{paragraph}</p>
                  <div class="play-choices">
                    <button
                      :for={{choice, c} <- Enum.with_index(entry.interaction["choices"])}
                      id={"choice-#{c}"}
                      class="play-place"
                      phx-click="complete_interaction"
                      phx-value-id={entry.interaction["id"]}
                      phx-value-choice={choice["id"]}
                      phx-value-turn={@player.turn}
                    >
                      <span>{choice["label"]}</span>
                    </button>
                  </div>
                  <button id="close-scene" phx-click="close_interaction">Close</button>
                </section>
              <% end %>
            </section>
            <section :if={@inspected} id="place-inspection" class="play-inspection">
              <h3>{@inspected["name"]}</h3><p>{@inspected["notes"]}</p>
              <button id="close-inspection" phx-click="close_inspect">Close</button>
            </section>
          <% end %>
          <div class="play-footer">
            <p>Your walk is saved after every step.</p>
            <button
              :if={@player || @error}
              id="new-walk"
              phx-click="new_walk"
              data-confirm="Start a new walk? This resets your saved turns and visited places."
            >New walk</button>
            <a href={~p"/?world=#{@world_name}"}>World editor</a>
            <a
              id="switch-graph"
              href={
                if @graph == :authored,
                  do: ~p"/play?world=#{@world_name}&graph=generated",
                  else: ~p"/play?world=#{@world_name}&graph=authored"
              }
            >
              {if @graph == :authored, do: "Play the generated map", else: "Play the authored map"}
            </a>
          </div>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
