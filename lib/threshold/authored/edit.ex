defmodule Threshold.Authored.Edit do
  @moduledoc """
  Pure edit operations on an authored document. Each returns `{:ok, doc}` or `{:error, message}`
  and re-validates the result, so a working copy is never invalid.

  Anchors coming from the browser are *requests*: node and edge references are resolved against
  the imported geography here (positions and shape hashes come from the index, not the client).
  """

  alias Threshold.Authored

  @type result :: {:ok, Authored.t()} | {:error, String.t()}

  # --- Locations ----------------------------------------------------------------------

  @doc "Adds a location. Returns the new document and the new location's id."
  @spec add_location(Authored.t(), map, Threshold.Geography.t()) ::
          {:ok, Authored.t(), String.t()} | {:error, String.t()}
  def add_location(doc, request, geography) do
    with {:ok, anchor} <- resolve_anchor(request, geography) do
      id = Authored.new_id("locations")
      location = %{"id" => id, "name" => "New location", "notes" => "", "anchor" => anchor}

      with {:ok, doc} <- finish(update_in(doc["locations"], &(&1 ++ [location]))),
           do: {:ok, doc, id}
    end
  end

  @spec update_location(Authored.t(), String.t(), map) :: result
  def update_location(doc, id, %{} = fields) do
    update_item(doc, "locations", id, fn loc ->
      loc |> put_string(fields, "name") |> put_string(fields, "notes")
    end)
  end

  @doc "Moves a location to a newly resolved anchor (this is also how a detached location is reconnected)."
  @spec move_location(Authored.t(), String.t(), map, Threshold.Geography.t()) :: result
  def move_location(doc, id, request, geography) do
    with {:ok, anchor} <- resolve_anchor(request, geography) do
      update_item(doc, "locations", id, &Map.put(&1, "anchor", anchor))
    end
  end

  @doc "Keeps a location but drops its geography reference, leaving it as a fictional free point."
  @spec detach_location(Authored.t(), String.t()) :: result
  def detach_location(doc, id) do
    update_item(doc, "locations", id, fn loc ->
      Map.put(loc, "anchor", %{"kind" => "point", "point" => loc["anchor"]["point"]})
    end)
  end

  @doc "Deletes a location and any connections that use it. Returns the removed connection ids."
  @spec delete_location(Authored.t(), String.t()) ::
          {:ok, Authored.t(), [String.t()]} | {:error, String.t()}
  def delete_location(doc, id) do
    if Enum.any?(doc["locations"], &(&1["id"] == id)) do
      {gone, kept} = Enum.split_with(doc["connections"], &(id in [&1["from"], &1["to"]]))

      doc =
        doc
        |> Map.update!("locations", &Enum.reject(&1, fn l -> l["id"] == id end))
        |> Map.put("connections", kept)

      with {:ok, doc} <- finish(doc), do: {:ok, doc, Enum.map(gone, & &1["id"])}
    else
      {:error, "No such location."}
    end
  end

  # --- Connections --------------------------------------------------------------------

  @spec add_connection(Authored.t(), String.t(), String.t()) ::
          {:ok, Authored.t(), String.t()} | {:error, String.t()}
  def add_connection(doc, from, to) do
    cond do
      from == to ->
        {:error, "A connection needs two different locations."}

      Enum.any?(
        doc["connections"],
        &(MapSet.new([&1["from"], &1["to"]]) == MapSet.new([from, to]))
      ) ->
        {:error, "Those locations are already connected."}

      true ->
        id = Authored.new_id("connections")
        conn = %{"id" => id, "from" => from, "to" => to, "kind" => "fictional", "notes" => ""}

        with {:ok, doc} <- finish(update_in(doc["connections"], &(&1 ++ [conn]))),
             do: {:ok, doc, id}
    end
  end

  @spec update_connection(Authored.t(), String.t(), map) :: result
  def update_connection(doc, id, fields),
    do: update_item(doc, "connections", id, &put_string(&1, fields, "notes"))

  @spec delete(Authored.t(), String.t(), String.t()) :: result
  def delete(doc, collection, id) when collection in ["connections", "closures"] do
    if Enum.any?(doc[collection], &(&1["id"] == id)),
      do: finish(update_in(doc[collection], &Enum.reject(&1, fn i -> i["id"] == id end))),
      else: {:error, "Nothing to delete."}
  end

  # --- Closures -----------------------------------------------------------------------

  @doc "Closes (restricts) an imported edge. If the edge is already closed, returns the existing closure's id."
  @spec add_closure(Authored.t(), String.t(), Threshold.Geography.t()) ::
          {:ok, Authored.t(), String.t()} | {:error, String.t()}
  def add_closure(doc, edge, geography) do
    case Enum.find(doc["closures"], &(&1["edge"] == edge)) do
      %{"id" => id} ->
        {:ok, doc, id}

      nil ->
        case Map.fetch(geography.edges, edge) do
          {:ok, hash} ->
            id = Authored.new_id("closures")

            closure = %{
              "id" => id,
              "edge" => edge,
              "kind" => "restricted",
              "reason" => "",
              "geometry_hash" => hash
            }

            with {:ok, doc} <- finish(update_in(doc["closures"], &(&1 ++ [closure]))),
                 do: {:ok, doc, id}

          :error ->
            {:error, "That edge is not in the imported geography."}
        end
    end
  end

  @doc "Explicitly reattaches a closure, preserving its identity and reason."
  @spec reconnect_closure(Authored.t(), String.t(), String.t(), Threshold.Geography.t()) :: result
  def reconnect_closure(doc, id, edge, geography) do
    cond do
      not Enum.any?(doc["closures"], &(&1["id"] == id)) ->
        {:error, "No such closure."}

      not Map.has_key?(geography.edges, edge) ->
        {:error, "That street is not in the imported geography."}

      Enum.any?(doc["closures"], &(&1["id"] != id and &1["edge"] == edge)) ->
        {:error, "That street already has a closure."}

      true ->
        update_item(doc, "closures", id, fn closure ->
          closure |> Map.put("edge", edge) |> Map.put("geometry_hash", geography.edges[edge])
        end)
    end
  end

  @spec update_closure(Authored.t(), String.t(), map) :: result
  def update_closure(doc, id, fields),
    do: update_item(doc, "closures", id, &put_string(&1, fields, "reason"))

  # --- Playable-location overrides ----------------------------------------------------

  @doc """
  Records a designer decision about a candidate playable location: `"retain"` keeps it through
  simplification, `"suppress"` lets it be simplified away. `nil` clears the decision. Overrides take
  effect when the playable layer is next regenerated.
  """
  @spec set_playable_override(Authored.t(), String.t(), String.t() | nil) :: result
  def set_playable_override(doc, id, action) do
    others = Enum.reject(doc["playable_overrides"], &(&1["id"] == id))
    list = if action, do: others ++ [%{"id" => id, "action" => action}], else: others
    finish(Map.put(doc, "playable_overrides", list))
  end

  # --- Anchors ------------------------------------------------------------------------

  @doc false
  def resolve_anchor(%{"kind" => "point", "point" => [lon, lat]}, _geography)
      when is_number(lon) and is_number(lat) do
    {:ok, %{"kind" => "point", "point" => [lon, lat]}}
  end

  def resolve_anchor(%{"kind" => "node", "ref" => ref}, geography) do
    case Map.fetch(geography.nodes, ref) do
      {:ok, point} -> {:ok, %{"kind" => "node", "ref" => ref, "point" => point}}
      :error -> {:error, "That intersection is not in the imported geography."}
    end
  end

  def resolve_anchor(
        %{"kind" => "edge", "ref" => ref, "offset" => offset, "point" => [lon, lat]},
        geography
      )
      when is_number(offset) and is_number(lon) and is_number(lat) do
    case Map.fetch(geography.edges, ref) do
      {:ok, hash} ->
        {:ok,
         %{
           "kind" => "edge",
           "ref" => ref,
           "offset" => min(max(offset, 0), 1),
           "point" => [lon, lat],
           "ref_geometry_hash" => hash
         }}

      :error ->
        {:error, "That street is not in the imported geography."}
    end
  end

  def resolve_anchor(_, _), do: {:error, "Could not understand that position."}

  # --- helpers ------------------------------------------------------------------------

  defp update_item(doc, collection, id, fun) do
    if Enum.any?(doc[collection], &(&1["id"] == id)) do
      finish(
        update_in(doc[collection], fn items ->
          Enum.map(items, &if(&1["id"] == id, do: fun.(&1), else: &1))
        end)
      )
    else
      {:error, "No such #{String.trim_trailing(collection, "s")}."}
    end
  end

  defp put_string(item, fields, key) do
    case fields do
      %{^key => value} when is_binary(value) -> Map.put(item, key, String.slice(value, 0, 2000))
      _ -> item
    end
  end

  defp finish(doc) do
    case Authored.validate(doc) do
      {:ok, doc} -> {:ok, doc}
      {:error, [first | _]} -> {:error, "Edit rejected: #{first}"}
    end
  end
end
