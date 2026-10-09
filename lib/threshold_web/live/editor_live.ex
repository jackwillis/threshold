defmodule ThresholdWeb.EditorLive do
  @moduledoc """
  Map editor. The server owns the working copy of the authored layer and the boundary; the map is
  a view of it (the `MapEditor` JS hook reads `data-state`) and reports gestures back as events.
  Nothing touches disk until Save, which refuses to overwrite files changed in the meantime.
  """
  use ThresholdWeb, :live_view

  import ThresholdWeb.EditorComponents

  alias Threshold.Authored
  alias Threshold.Authored.Edit
  alias Threshold.{Boundary, Geography, References, World}

  # Single source for the palette: it drives the legend here and the map via data-state.
  @palette %{
    "access_status" => [
      {"public", "#2e9e5b"},
      {"unknown", "#8b95a1"},
      {"conditional", "#e0a020"},
      {"restricted", "#d64545"},
      {"mixed", "#8e5bd6"}
    ],
    "classification" => [{"street", "#3b4a5a"}, {"alley", "#d98324"}, {"path", "#2f7fc1"}],
    # Why access_status has its value: a tag on the way, OSM's default for the highway type, or neither.
    "access_basis" => [
      {"explicit", "#2f7fc1"},
      {"default_allowed", "#2e9e5b"},
      {"uncertain", "#e0a020"}
    ]
  }

  @layer_options [
    {"edges", "Streets and paths"},
    {"nodes", "Intersections (nodes)"},
    {"buildings", "Buildings"},
    {"plazas", "Pedestrian areas"},
    {"parks", "Parks"},
    {"water", "Water"},
    {"vertical", "Elevators / vertical"},
    {"boundary", "Playable boundary"},
    {"extent", "Import extent (buffer)"},
    {"authored", "Authored layer"}
  ]

  @color_options [
    {"Access", "access_status"},
    {"Type", "classification"},
    {"Component", "component"}
  ]

  @modes ~w(inspect place move connect close boundary)

  @impl true
  def mount(params, _session, socket) do
    name = params["world"] || World.default_name()

    case World.load(name) do
      {:ok, _world} ->
        {:ok,
         socket
         |> assign(:page_title, "Editor")
         |> assign(:loading, true)
         |> assign(:load_error, nil)
         |> assign(:rev, 0)
         |> assign(:focus, %{"n" => 0, "bounds" => nil, "object" => nil})
         |> assign(:layer_options, @layer_options)
         |> assign(:color_options, @color_options)
         |> assign(:palette, @palette)
         |> load_world(name)
         |> assign_view(%{"color_by" => "access_status", "layers" => default_layers()})}

      {:error, :not_found} ->
        {:ok,
         socket |> put_flash(:error, "World #{inspect(name)} not found") |> assign(:world, nil)}
    end
  end

  # (Re)reads everything from disk, discarding any working copy.
  defp load_world(socket, name) do
    {:ok, world} = World.load(name)
    dir = world.dir
    geography = with {:ok, g} <- Geography.index(dir), do: g

    socket =
      socket
      |> assign(:world, world)
      |> assign(:geography, if(is_map(geography), do: geography))
      |> assign(:boundary, world.boundary["geometry"])
      |> assign(:saved_boundary, world.boundary["geometry"])
      |> assign(:boundary_hash, world.boundary_hash)
      |> assign(:mode, "inspect")
      |> assign(:pending_from, nil)
      |> assign(:selected, nil)

    # An invalid authored file is reported and never "fixed"; editing is disabled while it is invalid.
    case Authored.load(dir) do
      {:ok, authored, hash} ->
        socket
        |> assign(:authored, authored)
        |> assign(:saved_authored, authored)
        |> assign(:authored_hash, hash)
        |> assign(:authored_errors, [])
        |> refresh_refs()

      {:error, errors} ->
        socket
        |> assign(:authored, Authored.empty())
        |> assign(:saved_authored, Authored.empty())
        |> assign(:authored_hash, nil)
        |> assign(:authored_errors, errors)
        |> assign(:refs, [])
    end
  end

  defp refresh_refs(%{assigns: %{geography: nil}} = socket), do: assign(socket, :refs, [])

  defp refresh_refs(%{assigns: a} = socket),
    do: assign(socket, :refs, References.resolve(a.authored, a.geography))

  defp default_layers, do: Map.new(@layer_options, fn {key, _} -> {key, key != "nodes"} end)

  defp assign_view(socket, %{"color_by" => color_by, "layers" => layers}) do
    form = layers |> Map.put("color_by", color_by) |> then(&to_form(&1, as: :view))
    socket |> assign(:color_by, color_by) |> assign(:layers, layers) |> assign(:form, form)
  end

  defp editable?(assigns), do: assigns.authored_errors == [] and assigns.geography != nil

  defp dirty?(a), do: a.authored != a.saved_authored or a.boundary != a.saved_boundary

  # --- Events -------------------------------------------------------------------------

  @impl true
  def handle_event("view", %{"view" => params}, socket) do
    layers = Map.new(socket.assigns.layers, fn {key, _} -> {key, params[key] == "true"} end)

    {:noreply,
     assign_view(socket, %{
       "color_by" => params["color_by"] || socket.assigns.color_by,
       "layers" => layers
     })}
  end

  # Forms use phx-change only; this stops Enter from submitting them natively.
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("map_loaded", _params, socket),
    do: {:noreply, assign(socket, loading: false, load_error: nil)}

  def handle_event("map_failed", %{"message" => message}, socket),
    do: {:noreply, assign(socket, loading: false, load_error: message)}

  def handle_event("focus_component", %{"index" => index}, socket) do
    index = String.to_integer(index)
    component = Enum.find(components(socket.assigns.world), &(&1["component"] == index))
    {:noreply, focus(socket, %{"bounds" => component && component["bounds"], "object" => nil})}
  end

  def handle_event("focus_object", %{"id" => id}, socket),
    do: {:noreply, focus(socket, %{"bounds" => nil, "object" => id})}

  def handle_event("set_mode", %{"mode" => mode}, socket) when mode in @modes do
    if mode == "inspect" or editable?(socket.assigns) do
      {:noreply, socket |> assign(:mode, mode) |> assign(:pending_from, nil)}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "Editing is disabled until authored.json is valid and geography is built."
       )}
    end
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, socket |> assign(:selected, nil) |> assign(:pending_from, nil)}
  end

  # A click on the map. What it means depends on the active tool.
  def handle_event("pick", %{"layer" => layer, "id" => id} = params, socket) do
    {:noreply, pick(socket.assigns.mode, layer, id, params["properties"] || %{}, socket)}
  end

  def handle_event("add_location", %{"anchor" => request}, socket) do
    with :ok <- allow_edit(socket),
         {:ok, doc, id} <-
           Edit.add_location(socket.assigns.authored, request, socket.assigns.geography) do
      {:noreply,
       socket |> apply_edit(doc) |> select("authored-location", id) |> assign(:mode, "inspect")}
    else
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("move_location", %{"id" => id, "anchor" => request}, socket) do
    with :ok <- allow_edit(socket),
         {:ok, doc} <-
           Edit.move_location(socket.assigns.authored, id, request, socket.assigns.geography) do
      {:noreply, socket |> apply_edit(doc) |> bump_rev()}
    else
      {:error, message} -> {:noreply, socket |> put_flash(:error, message) |> bump_rev()}
    end
  end

  def handle_event("update_location", %{"location" => %{"id" => id} = fields}, socket),
    do: edit(socket, &Edit.update_location(&1, id, fields))

  def handle_event("update_connection", %{"connection" => %{"id" => id} = fields}, socket),
    do: edit(socket, &Edit.update_connection(&1, id, fields))

  def handle_event("update_closure", %{"closure" => %{"id" => id} = fields}, socket),
    do: edit(socket, &Edit.update_closure(&1, id, fields))

  def handle_event("detach_location", %{"id" => id}, socket),
    do: edit(socket, &Edit.detach_location(&1, id))

  def handle_event("close_edge", %{"id" => id}, socket) do
    case Edit.add_closure(socket.assigns.authored, id, socket.assigns.geography) do
      {:ok, doc, closure_id} ->
        {:noreply, socket |> apply_edit(doc) |> select("authored-closure", closure_id)}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event(
        "delete_selected",
        _params,
        %{assigns: %{selected: %{layer: "authored-location", id: id}}} = socket
      ) do
    case Edit.delete_location(socket.assigns.authored, id) do
      {:ok, doc, removed} ->
        {:noreply,
         socket
         |> apply_edit(doc)
         |> assign(:selected, nil)
         |> put_flash(:info, deleted_message(removed))}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event(
        "delete_selected",
        _params,
        %{assigns: %{selected: %{layer: "authored-connection", id: id}}} = socket
      ),
      do: delete_item(socket, "connections", id)

  def handle_event(
        "delete_selected",
        _params,
        %{assigns: %{selected: %{layer: "authored-closure", id: id}}} = socket
      ),
      do: delete_item(socket, "closures", id)

  def handle_event("delete_selected", _params, socket), do: {:noreply, socket}

  def handle_event("update_boundary", %{"coordinates" => ring}, socket) do
    with :ok <- allow_edit(socket), {:ok, geometry} <- Boundary.polygon(ring) do
      {:noreply, socket |> assign(:boundary, geometry) |> bump_rev()}
    else
      {:error, message} -> {:noreply, socket |> put_flash(:error, message) |> bump_rev()}
    end
  end

  def handle_event("discard", _params, socket) do
    {:noreply,
     socket
     |> load_world(socket.assigns.world.name)
     |> put_flash(:info, "Changes discarded; reloaded from disk.")}
  end

  def handle_event("save", _params, socket) do
    {socket, notes} = save_authored(socket, socket.assigns, [])
    {socket, notes} = save_boundary(socket, socket.assigns, notes)
    notes = Enum.reverse(notes)

    socket =
      case Enum.find(notes, &match?({:error, _}, &1)) do
        {:error, message} ->
          put_flash(socket, :error, message)

        nil ->
          if notes == [],
            do: socket,
            else: put_flash(socket, :info, notes |> Enum.map(&elem(&1, 1)) |> Enum.join(" "))
      end

    {:noreply, socket}
  end

  # --- Event helpers ------------------------------------------------------------------

  # Tells the map to re-sync its drawing layer even if the server data did not change (e.g. a rejected edit).
  defp bump_rev(socket), do: update(socket, :rev, &(&1 + 1))

  defp focus(socket, attrs),
    do: assign(socket, :focus, Map.merge(%{"n" => socket.assigns.focus["n"] + 1}, attrs))

  defp pick("connect", "authored-location", id, _props, socket) do
    case socket.assigns.pending_from do
      nil ->
        assign(socket, :pending_from, id)

      ^id ->
        assign(socket, :pending_from, nil)

      from ->
        case Edit.add_connection(socket.assigns.authored, from, id) do
          {:ok, doc, conn_id} ->
            socket
            |> apply_edit(doc)
            |> assign(:pending_from, nil)
            |> select("authored-connection", conn_id)

          {:error, message} ->
            socket |> assign(:pending_from, nil) |> put_flash(:error, message)
        end
    end
  end

  defp pick("connect", _layer, _id, _props, socket), do: socket

  defp pick("close", "edges", id, _props, socket) do
    case Edit.add_closure(socket.assigns.authored, id, socket.assigns.geography) do
      {:ok, doc, closure_id} ->
        socket |> apply_edit(doc) |> select("authored-closure", closure_id)

      {:error, message} ->
        put_flash(socket, :error, message)
    end
  end

  defp pick("close", _layer, _id, _props, socket), do: socket

  defp pick(_mode, layer, id, props, socket),
    do: assign(socket, :selected, %{layer: layer, id: id, properties: props})

  defp select(socket, layer, id),
    do: assign(socket, :selected, %{layer: layer, id: id, properties: %{}})

  defp deleted_message([]), do: "Location deleted."

  defp deleted_message(removed),
    do: "Location deleted along with #{length(removed)} connection(s)."

  defp delete_item(socket, collection, id) do
    case Edit.delete(socket.assigns.authored, collection, id) do
      {:ok, doc} -> {:noreply, socket |> apply_edit(doc) |> assign(:selected, nil)}
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp allow_edit(socket),
    do: if(editable?(socket.assigns), do: :ok, else: {:error, "Editing is disabled."})

  defp edit(socket, fun) do
    case fun.(socket.assigns.authored) do
      {:ok, doc} -> {:noreply, apply_edit(socket, doc)}
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp apply_edit(socket, doc), do: socket |> assign(:authored, doc) |> refresh_refs()

  # --- Saving ------------------------------------------------------------------------

  defp save_authored(socket, a, notes) do
    if a.authored != a.saved_authored do
      case Authored.save(a.world.dir, a.authored, a.authored_hash) do
        {:ok, hash} ->
          {socket |> assign(:saved_authored, a.authored) |> assign(:authored_hash, hash),
           [{:ok, "Authored layer saved."} | notes]}

        {:error, :conflict} ->
          {socket, [{:error, conflict_message("authored.json")} | notes]}

        {:error, other} ->
          {socket, [{:error, "Could not save authored.json: #{inspect(other)}"} | notes]}
      end
    else
      {socket, notes}
    end
  end

  defp save_boundary(socket, a, notes) do
    if a.boundary != a.saved_boundary do
      case Boundary.save(a.world.dir, a.boundary, a.boundary_hash, a.world.config) do
        {:ok, hash} ->
          # Reloading the world recomputes staleness: the geography no longer matches the boundary.
          {:ok, world} = World.load(a.world.name)

          {socket
           |> assign(:world, world)
           |> assign(:saved_boundary, a.boundary)
           |> assign(:boundary_hash, hash),
           [{:ok, "Boundary saved. Regenerate the geography with `make build-world`."} | notes]}

        {:error, :conflict} ->
          {socket, [{:error, conflict_message("boundary.geojson")} | notes]}

        {:error, message} when is_binary(message) ->
          {socket, [{:error, message} | notes]}

        {:error, other} ->
          {socket, [{:error, "Could not save boundary.geojson: #{inspect(other)}"} | notes]}
      end
    else
      {socket, notes}
    end
  end

  defp conflict_message(file),
    do:
      "#{file} changed on disk since you opened it, so nothing was overwritten. Discard your changes to reload it."

  # --- State sent to the map ----------------------------------------------------------

  defp components(%{provenance: %{"summary" => %{"components" => list}}}), do: list
  defp components(_), do: []

  defp ref_status(refs) do
    rank = %{missing: 2, moved: 1, ok: 0}

    refs
    |> Enum.group_by(& &1.object, & &1.status)
    |> Map.new(fn {object, statuses} ->
      {object, statuses |> Enum.max_by(&rank[&1]) |> Atom.to_string()}
    end)
  end

  defp map_state(assigns) do
    Jason.encode!(%{
      layers: assigns.layers,
      colorBy: assigns.color_by,
      focus: assigns.focus,
      authored: assigns.authored,
      refStatus: ref_status(assigns.refs),
      boundary: assigns.boundary,
      mode: assigns.mode,
      selected: assigns.selected && assigns.selected.id,
      pendingFrom: assigns.pending_from,
      dirty: dirty?(assigns),
      rev: assigns.rev,
      palette: Map.new(assigns.palette, fn {key, entries} -> {key, Map.new(entries)} end)
    })
  end

  defp summary(world, key), do: get_in(world.provenance || %{}, ["summary", key]) || %{}

  defp legend_count(world, "access_status", value),
    do: summary(world, "edges_by_access")[value] || 0

  defp legend_count(world, color_by, value),
    do: summary(world, "edges_by_#{color_by}")[value] || 0

  @impl true
  def render(%{world: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <p class="empty-state">World not found.</p>
    </Layouts.app>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, dirty: dirty?(assigns), editable: editable?(assigns))

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="editor">
        <aside id="side-panel" class="panel">
          <h2 class="panel-title">{@world.config["name"]}</h2>

          <div :if={@world.staleness == :missing} id="stale-banner" class="banner banner-warn">
            No generated geography yet. Run <code>make build-world</code>.
          </div>
          <div
            :if={match?({:stale, _}, @world.staleness)}
            id="stale-banner"
            class="banner banner-warn"
          >
            <strong>Geography is out of date.</strong>
            <ul>
              <li :for={reason <- elem(@world.staleness, 1)}>{reason}</li>
            </ul>
            Run <code>make build-world</code>
            to regenerate.
          </div>

          <div :if={@authored_errors != []} id="authored-errors" class="banner banner-error">
            <strong>authored.json is invalid and was not loaded. Editing is disabled.</strong>
            <ul>
              <li :for={error <- Enum.take(@authored_errors, 8)}>{error}</li>
            </ul>
            <span :if={length(@authored_errors) > 8}>…and {length(@authored_errors) - 8} more.</span>
          </div>

          <.form for={@form} id="view-form" phx-change="view">
            <fieldset>
              <legend>Layers</legend>
              <.input
                :for={{key, label} <- @layer_options}
                field={@form[key]}
                type="checkbox"
                label={label}
              />
            </fieldset>
            <.input
              field={@form[:color_by]}
              type="select"
              label="Color streets by"
              options={@color_options}
            />
          </.form>

          <section id="legend">
            <h3>Legend</h3>
            <%= case Map.fetch(@palette, @color_by) do %>
              <% {:ok, entries} -> %>
                <ul class="legend">
                  <li :for={{value, color} <- entries}>
                    <span class="swatch" style={"background: #{color}"}></span>{value}
                    <span class="count">{legend_count(@world, @color_by, value)}</span>
                  </li>
                </ul>
              <% :error -> %>
                <p class="hint">
                  Each color is one connected component. The main network is slate; separate colors mark disconnected pieces.
                </p>
            <% end %>
          </section>

          <section id="authored">
            <h3>Authored</h3>
            <p class="hint">
              {length(@authored["locations"])} locations · {length(@authored["connections"])} connections · {length(
                @authored["closures"]
              )} closures
            </p>
            <ul :if={References.needing_review(@refs) != []} id="review" class="review">
              <li :for={ref <- References.needing_review(@refs)} class={"review-#{ref.status}"}>
                <span class="badge">{ref.status}</span>
                <button
                  type="button"
                  phx-click="focus_object"
                  phx-value-id={ref.object}
                  class="link-button"
                  disabled={ref.status == :missing and String.starts_with?(ref.object, "clo:")}
                >
                  {ref.object}
                </button>
                <span class="hint">→ {ref.ref}</span>
              </li>
            </ul>
          </section>

          <section id="components">
            <h3>Components</h3>
            <ul class="components">
              <li :for={c <- Enum.take(components(@world), 12)}>
                <button
                  type="button"
                  phx-click="focus_component"
                  phx-value-index={c["component"]}
                  class="link-button"
                >
                  #{c["component"]}: {c["edges"]} edges, {round(c["length_m"])} m
                </button>
              </li>
            </ul>
            <p :if={length(components(@world)) > 12} class="hint">
              …and {length(components(@world)) - 12} more.
            </p>
          </section>

          <p class="notice">
            Presence on this map does not imply permission to enter. Access values come from OpenStreetMap tags and are often unknown.
          </p>
        </aside>

        <div
          id="map-hook"
          phx-hook="MapEditor"
          data-world={@world.name}
          data-state={map_state(assigns)}
          class="map-wrap"
        >
          <div id="map-canvas" phx-update="ignore"></div>
          <.toolbar mode={@mode} editable={@editable} pending_from={@pending_from} />
          <.save_bar dirty={@dirty} />
          <div :if={@loading} id="map-loading" class="map-status">Loading geography…</div>
          <div :if={@load_error} id="map-error" class="map-status map-status-error">
            {@load_error}
          </div>
        </div>

        <aside id="inspector" class="panel">
          <h2 class="panel-title">Inspector</h2>
          <.inspector selected={@selected} authored={@authored} refs={@refs} editable={@editable} />
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
