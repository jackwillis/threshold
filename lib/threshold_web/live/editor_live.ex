defmodule ThresholdWeb.EditorLive do
  @moduledoc """
  Map editor shell: layer controls, legend, components list and inspector. The map itself is
  owned by the `MapEditor` JS hook (assets/src/hooks), which reads `data-state` and reports
  selections back with `pushEvent`.
  """
  use ThresholdWeb, :live_view

  alias Threshold.{Authored, Geography, References, World}

  # Single source for the palette: it drives the legend here and the map via data-state.
  @palette %{
    "access_status" => [
      {"public", "#2e9e5b"},
      {"unknown", "#8b95a1"},
      {"conditional", "#e0a020"},
      {"restricted", "#d64545"},
      {"mixed", "#8e5bd6"}
    ],
    "classification" => [{"street", "#3b4a5a"}, {"alley", "#d98324"}, {"path", "#2f7fc1"}]
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

  @impl true
  def mount(params, _session, socket) do
    name = params["world"] || World.default_name()

    case World.load(name) do
      {:ok, world} ->
        {:ok,
         socket
         |> assign(:page_title, "Editor")
         |> assign(:world, world)
         |> assign(:loading, true)
         |> assign(:load_error, nil)
         |> assign(:selected, nil)
         |> assign(:focus, %{"n" => 0, "bounds" => nil, "object" => nil})
         |> assign(:layer_options, @layer_options)
         |> assign(:color_options, @color_options)
         |> assign(:palette, @palette)
         |> load_authored()
         |> assign_view(%{"color_by" => "access_status", "layers" => default_layers()})}

      {:error, :not_found} ->
        {:ok,
         socket |> put_flash(:error, "World #{inspect(name)} not found") |> assign(:world, nil)}
    end
  end

  # The authored file is the only one the editor writes. An invalid file is reported, never "fixed".
  defp load_authored(socket) do
    dir = socket.assigns.world.dir

    case Authored.load(dir) do
      {:ok, authored, hash} ->
        refs =
          case Geography.index(dir) do
            {:ok, geography} -> References.resolve(authored, geography)
            :error -> []
          end

        socket
        |> assign(:authored, authored)
        |> assign(:authored_hash, hash)
        |> assign(:authored_errors, [])
        |> assign(:refs, refs)

      {:error, errors} ->
        socket
        |> assign(:authored, Authored.empty())
        |> assign(:authored_hash, nil)
        |> assign(:authored_errors, errors)
        |> assign(:refs, [])
    end
  end

  # Worst status per authored object: missing > moved > ok.
  defp ref_status(refs) do
    rank = %{missing: 2, moved: 1, ok: 0}

    refs
    |> Enum.group_by(& &1.object, & &1.status)
    |> Map.new(fn {object, statuses} ->
      {object, statuses |> Enum.max_by(&rank[&1]) |> Atom.to_string()}
    end)
  end

  defp default_layers, do: Map.new(@layer_options, fn {key, _} -> {key, key != "nodes"} end)

  defp assign_view(socket, %{"color_by" => color_by, "layers" => layers}) do
    form =
      layers
      |> Map.put("color_by", color_by)
      |> then(&to_form(&1, as: :view))

    socket |> assign(:color_by, color_by) |> assign(:layers, layers) |> assign(:form, form)
  end

  @impl true
  def handle_event("view", %{"view" => params}, socket) do
    layers = Map.new(socket.assigns.layers, fn {key, _} -> {key, params[key] == "true"} end)

    {:noreply,
     assign_view(socket, %{
       "color_by" => params["color_by"] || socket.assigns.color_by,
       "layers" => layers
     })}
  end

  def handle_event("map_loaded", _params, socket),
    do: {:noreply, assign(socket, loading: false, load_error: nil)}

  def handle_event("map_failed", %{"message" => message}, socket) do
    {:noreply, assign(socket, loading: false, load_error: message)}
  end

  def handle_event("select", %{"layer" => layer, "id" => id, "properties" => props}, socket) do
    {:noreply, assign(socket, :selected, %{layer: layer, id: id, properties: props})}
  end

  def handle_event("clear_selection", _params, socket),
    do: {:noreply, assign(socket, :selected, nil)}

  def handle_event("focus_component", %{"index" => index}, socket) do
    index = String.to_integer(index)
    component = Enum.find(components(socket.assigns.world), &(&1["component"] == index))
    focus = %{"n" => socket.assigns.focus["n"] + 1, "bounds" => component && component["bounds"]}
    {:noreply, assign(socket, :focus, focus)}
  end

  def handle_event("focus_object", %{"id" => id}, socket) do
    focus = %{"n" => socket.assigns.focus["n"] + 1, "bounds" => nil, "object" => id}
    {:noreply, assign(socket, :focus, focus)}
  end

  defp components(%{provenance: %{"summary" => %{"components" => list}}}), do: list
  defp components(_), do: []

  defp map_state(assigns) do
    Jason.encode!(%{
      layers: assigns.layers,
      colorBy: assigns.color_by,
      focus: assigns.focus,
      authored: assigns.authored,
      refStatus: ref_status(assigns.refs),
      palette: Map.new(assigns.palette, fn {key, entries} -> {key, Map.new(entries)} end)
    })
  end

  defp summary(world, key), do: get_in(world.provenance || %{}, ["summary", key]) || %{}

  defp legend_count(world, "access_status", value),
    do: summary(world, "edges_by_access")[value] || 0

  defp legend_count(world, color_by, value),
    do: summary(world, "edges_by_#{color_by}")[value] || 0

  defp hidden_property?(key), do: key in ["id", "edges", "osm_ids", "geometry_hash"]

  defp format_value(value) when is_list(value), do: Enum.join(value, ", ")

  defp format_value(value) when is_binary(value) or is_number(value) or is_boolean(value),
    do: to_string(value)

  defp format_value(nil), do: "–"
  defp format_value(value), do: inspect(value)

  defp osm_links(%{"osm_ids" => ids}) when is_list(ids),
    do: for(id <- ids, do: {"way #{id}", "https://www.openstreetmap.org/way/#{id}"})

  defp osm_links(%{"osm_type" => type, "osm_id" => id}) when is_binary(type),
    do: [{"#{type} #{id}", "https://www.openstreetmap.org/#{type}/#{id}"}]

  defp osm_links(%{"osm_id" => id}),
    do: [{"node #{id}", "https://www.openstreetmap.org/node/#{id}"}]

  defp osm_links(_), do: []

  @impl true
  def render(%{world: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <p class="empty-state">World not found.</p>
    </Layouts.app>
    """
  end

  def render(assigns) do
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
            <strong>authored.json is invalid and was not loaded.</strong>
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
          <div :if={@loading} id="map-loading" class="map-status">Loading geography…</div>
          <div :if={@load_error} id="map-error" class="map-status map-status-error">
            {@load_error}
          </div>
        </div>

        <aside id="inspector" class="panel">
          <h2 class="panel-title">Inspector</h2>
          <%= if @selected do %>
            <h3 class="mono">{@selected.id}</h3>
            <p class="hint">{@selected.layer} · {@selected.properties["classification"]}</p>
            <ul class="osm-links">
              <li :for={{label, url} <- osm_links(@selected.properties)}>
                <a href={url} target="_blank" rel="noreferrer">{label} on OpenStreetMap</a>
              </li>
            </ul>
            <dl class="props">
              <%= for {key, value} <- Enum.sort(@selected.properties), not hidden_property?(key) do %>
                <dt>{key}</dt>
                <dd>{format_value(value)}</dd>
              <% end %>
            </dl>
            <p :if={is_list(@selected.properties["edges"])} class="hint">
              {length(@selected.properties["edges"])} incident edges
            </p>
            <button type="button" phx-click="clear_selection" class="link-button">Clear selection</button>
          <% else %>
            <p class="hint">Click a street, intersection or building on the map.</p>
          <% end %>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
