defmodule ThresholdWeb.EditorComponents do
  @moduledoc "Toolbar, save bar and inspector for the editor."
  use ThresholdWeb, :html

  alias Threshold.References

  @tools [
    {"inspect", "Inspect"},
    {"place", "Place"},
    {"move", "Move"},
    {"connect", "Connect"},
    {"close", "Close street"},
    {"boundary", "Boundary"}
  ]

  attr :mode, :string, required: true
  attr :editable, :boolean, required: true
  attr :pending_from, :string, default: nil

  attr :reconnecting, :map, default: nil

  def toolbar(assigns) do
    assigns = assign(assigns, :tools, @tools)

    ~H"""
    <div id="toolbar" class="toolbar">
      <div class="tools">
        <button
          :for={{mode, label} <- @tools}
          id={"tool-#{mode}"}
          type="button"
          phx-click="set_mode"
          phx-value-mode={mode}
          disabled={mode != "inspect" and not @editable}
          class={["tool", @mode == mode && "tool-active"]}
        >
          {label}
        </button>
      </div>
      <p id="tool-hint" class="tool-hint">
        {if @mode == "reconnect",
          do: reconnect_hint(@reconnecting),
          else: tool_hint(@mode, @pending_from)}
      </p>
    </div>
    """
  end

  defp reconnect_hint(%{layer: "authored-location"}),
    do:
      "Click near a visible intersection or street to reconnect the location. Press Escape to cancel."

  defp reconnect_hint(_), do: "Click a street to reconnect the closure. Press Escape to cancel."

  defp tool_hint("inspect", _), do: "Click a feature to inspect it."

  defp tool_hint("place", _),
    do:
      "Click the map to place a location. It snaps to a nearby intersection or street, otherwise it is a free point."

  defp tool_hint("move", _),
    do: "Click a location to select it, then drag it. It snaps again when dropped."

  defp tool_hint("connect", nil), do: "Click the first location."
  defp tool_hint("connect", _), do: "Click the second location (click the same one to cancel)."
  defp tool_hint("close", _), do: "Click a street or path to close it."

  defp tool_hint("boundary", _),
    do:
      "Drag corners or midpoints to reshape the playable boundary. Saving makes the geography stale."

  attr :dirty, :boolean, required: true

  def save_bar(assigns) do
    ~H"""
    <div id="save-bar" class={["save-bar", @dirty && "save-bar-dirty"]}>
      <%= if @dirty do %>
        <span id="dirty-indicator">Unsaved changes</span>
        <button id="save-button" type="button" phx-click="save" class="tool tool-primary">Save</button>
        <button
          id="discard-button"
          type="button"
          phx-click="discard"
          class="tool"
          data-confirm="Discard all unsaved changes?"
        >Discard</button>
      <% else %>
        <span id="dirty-indicator" class="saved">All changes saved</span>
      <% end %>
    </div>
    """
  end

  attr :selected, :map, default: nil
  attr :authored, :map, required: true
  attr :refs, :list, required: true
  attr :editable, :boolean, required: true

  attr :geography, :map, default: nil

  def inspector(%{selected: nil} = assigns) do
    ~H"""
    <p class="hint">Click a street, intersection or building on the map.</p>
    """
  end

  def inspector(%{selected: %{layer: "authored-location", id: id}} = assigns) do
    assigns =
      assign(assigns, loc: Enum.find(assigns.authored["locations"], &(&1["id"] == id)), id: id)

    ~H"""
    <%= if @loc do %>
      <h3 class="mono">{@id}</h3>
      <p class="hint">
        authored location · {@loc["anchor"]["kind"]} anchor
        <.status_badge status={ref_status(@refs, @id)} />
      </p>
      <.form
        for={to_form(%{"id" => @id, "name" => @loc["name"], "notes" => @loc["notes"]}, as: :location)}
        id={"location-form-#{dom_id(@id)}"}
        phx-change="update_location"
        phx-submit="noop"
      >
        <input type="hidden" name="location[id]" value={@id} />
        <label class="field">Name
        <input
          type="text"
          name="location[name]"
          value={@loc["name"]}
          phx-debounce="300"
          disabled={not @editable}
        /></label>
        <label class="field">Notes <textarea
          name="location[notes]"
          rows="4"
          phx-debounce="300"
          disabled={not @editable}
        >{@loc["notes"]}</textarea></label>
      </.form>
      <dl class="props">
        <dt>position</dt>
        <dd>{Enum.map_join(@loc["anchor"]["point"], ", ", &Float.round(&1 * 1.0, 6))}</dd>
        <dt :if={@loc["anchor"]["ref"]}>anchored to</dt>
        <dd :if={@loc["anchor"]["ref"]} class="mono">{@loc["anchor"]["ref"]}</dd>
      </dl>
      <button
        :if={@loc["anchor"]["ref"] != nil and ref_status(@refs, @id) != "missing"}
        type="button"
        phx-click="focus_object"
        phx-value-id={@loc["anchor"]["ref"]}
        class="link-button"
      >View current geographic feature</button>
      <p :if={ref_status(@refs, @id) in ["missing", "moved"]} class="hint">
        The imported geography this is anchored to {if ref_status(@refs, @id) == "missing",
          do: "no longer exists",
          else: "has changed"}. Reconnect it to current geography, or keep it as a free point.
      </p>
      <p :if={@loc["anchor"]["kind"] == "node" and @geography} class="hint">
        Current intersection position: {format_position(@geography.nodes[@loc["anchor"]["ref"]])}
      </p>
      <div class="actions">
        <button
          id="reconnect-location"
          type="button"
          phx-click="start_reconnect"
          disabled={not @editable}
          class="tool"
        >Reconnect to geography</button>
        <button
          :if={@loc["anchor"]["kind"] != "point"}
          type="button"
          phx-click="detach_location"
          phx-value-id={@id}
          disabled={not @editable}
          class="tool"
        >Keep as free point</button>
        <button
          type="button"
          phx-click="delete_selected"
          disabled={not @editable}
          class="tool tool-danger"
        >Delete location</button>
      </div>
    <% else %>
      <p class="hint">That location no longer exists.</p>
    <% end %>
    """
  end

  def inspector(%{selected: %{layer: "authored-connection", id: id}} = assigns) do
    conn = Enum.find(assigns.authored["connections"], &(&1["id"] == id))

    assigns =
      assign(assigns,
        conn: conn,
        id: id,
        names: Map.new(assigns.authored["locations"], &{&1["id"], &1["name"]})
      )

    ~H"""
    <%= if @conn do %>
      <h3 class="mono">{@id}</h3>
      <p class="hint">authored connection · {@conn["kind"]}</p>
      <p>{@names[@conn["from"]]} ↔ {@names[@conn["to"]]}</p>
      <.form
        for={to_form(%{"id" => @id, "notes" => @conn["notes"]}, as: :connection)}
        id={"connection-form-#{dom_id(@id)}"}
        phx-change="update_connection"
        phx-submit="noop"
      >
        <input type="hidden" name="connection[id]" value={@id} />
        <label class="field">Notes <textarea
          name="connection[notes]"
          rows="4"
          phx-debounce="300"
          disabled={not @editable}
        >{@conn["notes"]}</textarea></label>
      </.form>
      <div class="actions">
        <button
          type="button"
          phx-click="delete_selected"
          disabled={not @editable}
          class="tool tool-danger"
        >Delete connection</button>
      </div>
    <% else %>
      <p class="hint">That connection no longer exists.</p>
    <% end %>
    """
  end

  def inspector(%{selected: %{layer: "authored-closure", id: id}} = assigns) do
    closure = Enum.find(assigns.authored["closures"], &(&1["id"] == id))
    assigns = assign(assigns, closure: closure, id: id)

    ~H"""
    <%= if @closure do %>
      <h3 class="mono">{@id}</h3>
      <p class="hint">
        authored closure · {@closure["kind"]} <.status_badge status={ref_status(@refs, @id)} />
      </p>
      <p class="mono">{@closure["edge"]}</p>
      <.form
        for={to_form(%{"id" => @id, "reason" => @closure["reason"]}, as: :closure)}
        id={"closure-form-#{dom_id(@id)}"}
        phx-change="update_closure"
        phx-submit="noop"
      >
        <input type="hidden" name="closure[id]" value={@id} />
        <label class="field">Reason
        <input
          type="text"
          name="closure[reason]"
          value={@closure["reason"]}
          phx-debounce="300"
          disabled={not @editable}
        /></label>
      </.form>
      <p class="hint">The imported access value is unchanged and still visible on the street.</p>
      <dl class="props">
        <dt>recorded shape</dt><dd class="mono">{@closure["geometry_hash"]}</dd>
        <dt>current shape</dt><dd class="mono">
          {if @geography, do: @geography.edges[@closure["edge"]] || "Missing", else: "Unavailable"}
        </dd>
      </dl>
      <button
        id="reconnect-closure"
        type="button"
        phx-click="start_reconnect"
        disabled={not @editable}
        class="tool"
      >Reconnect to street</button>
      <div class="actions">
        <button
          type="button"
          phx-click="delete_selected"
          disabled={not @editable}
          class="tool tool-danger"
        >Remove closure</button>
      </div>
    <% else %>
      <p class="hint">That closure no longer exists.</p>
    <% end %>
    """
  end

  def inspector(%{selected: %{layer: "playable-location", id: id, properties: props}} = assigns) do
    override =
      Enum.find_value(assigns.authored["playable_overrides"], &(&1["id"] == id && &1["action"]))

    assigns = assign(assigns, id: id, props: props, override: override)

    ~H"""
    <h3 class="mono">{@id}</h3>
    <p class="hint">
      candidate playable location
      <span :if={@override} class={["badge", "badge-override"]}>{@override}</span>
    </p>
    <dl class="props">
      <dt>why kept</dt>
      <dd>
        {if @props["reasons"] in [nil, []],
          do: "ordinary junction",
          else: Enum.join(@props["reasons"], ", ")}
      </dd>
      <dt>merges</dt>
      <dd>{@props["members"]} imported node(s)</dd>
      <dt>connections</dt>
      <dd>{@props["degree"]}</dd>
      <dt>component</dt>
      <dd>{@props["component"]}</dd>
    </dl>
    <div class="actions">
      <button
        type="button"
        phx-click="set_playable_override"
        phx-value-id={@id}
        phx-value-action="retain"
        disabled={not @editable}
        class={["tool", @override == "retain" && "tool-active"]}
      >Retain</button>
      <button
        type="button"
        phx-click="set_playable_override"
        phx-value-id={@id}
        phx-value-action="suppress"
        disabled={not @editable}
        class={["tool", @override == "suppress" && "tool-active"]}
      >Suppress</button>
      <button
        :if={@override}
        type="button"
        phx-click="set_playable_override"
        phx-value-id={@id}
        phx-value-action="clear"
        disabled={not @editable}
        class="tool"
      >Clear</button>
    </div>
    <p class="hint">
      Retain keeps this location through simplification; Suppress lets it be simplified away. The decision is saved with your authored changes and applies the next time the playable layer is built.
    </p>
    <button type="button" phx-click="clear_selection" class="link-button">Clear selection</button>
    """
  end

  def inspector(%{selected: %{layer: "playable-connection", id: id, properties: props}} = assigns) do
    assigns = assign(assigns, id: id, props: props)

    ~H"""
    <h3 class="mono">{@id}</h3>
    <p class="hint">candidate playable connection</p>
    <dl class="props">
      <dt>length</dt>
      <dd>{@props["length_m"]} m</dd>
      <dt>route types</dt>
      <dd>{Enum.join(@props["route_classes"] || @props["classes"] || [], ", ")}</dd>
      <dt>parallel routes</dt>
      <dd>{@props["parallel"]}</dd>
      <dt>underlying edges</dt>
      <dd>{length(@props["edge_ids"] || [])} (highlighted on the map)</dd>
    </dl>
    <button type="button" phx-click="clear_selection" class="link-button">Clear selection</button>
    """
  end

  def inspector(assigns) do
    closure = Enum.find(assigns.authored["closures"], &(&1["edge"] == assigns.selected.id))
    assigns = assign(assigns, closure: closure)

    ~H"""
    <h3 class="mono">{@selected.id}</h3>
    <p class="hint">{@selected.layer} · {@selected.properties["classification"]}</p>
    <ul class="osm-links">
      <li :for={{label, url} <- osm_links(@selected.properties)}>
        <a href={url} target="_blank" rel="noreferrer">{label} on OpenStreetMap</a>
      </li>
    </ul>
    <div :if={@selected.layer == "edges"} class="actions">
      <%= if @closure do %>
        <button
          type="button"
          phx-click="pick"
          phx-value-layer="authored-closure"
          phx-value-id={@closure["id"]}
          class="tool"
        >Closed: {@closure["reason"] |> blank_to("no reason")} (edit)</button>
      <% else %>
        <button
          type="button"
          phx-click="close_edge"
          phx-value-id={@selected.id}
          disabled={not @editable}
          class="tool"
        >Close this street</button>
      <% end %>
    </div>
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
    """
  end

  attr :status, :string, required: true

  defp status_badge(%{status: "ok"} = assigns), do: ~H""

  defp status_badge(assigns) do
    ~H"""
    <span class={["badge", "badge-#{@status}"]}>{@status}</span>
    """
  end

  defp ref_status(refs, id) do
    refs
    |> Enum.filter(&(&1.object == id))
    |> References.needing_review()
    |> Enum.map(& &1.status)
    |> Enum.max_by(&rank/1, fn -> :ok end)
    |> Atom.to_string()
  end

  defp rank(:missing), do: 2
  defp rank(:moved), do: 1
  defp rank(:ok), do: 0

  defp format_position(nil), do: "Missing"
  defp format_position(point), do: Enum.map_join(point, ", ", &Float.round(&1 * 1.0, 6))

  defp dom_id(id), do: String.replace(id, ":", "-")

  defp blank_to("", default), do: default
  defp blank_to(value, _default), do: value

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
end
