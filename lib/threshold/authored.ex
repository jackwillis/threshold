defmodule Threshold.Authored do
  @moduledoc """
  The authored layer (`authored.json`): fictional locations, connections and closures.

  This is the only world file the editor writes. It is validated strictly (unknown keys are
  errors, so typos cannot hide), written atomically with sorted keys for readable Git diffs,
  and saved only if the file on disk is unchanged since it was loaded.
  """

  @format_version 1
  @id_formats %{
    "locations" => ~r/\Aloc:[0-9a-z-]+\z/,
    "connections" => ~r/\Aconn:[0-9a-z-]+\z/,
    "closures" => ~r/\Aclo:[0-9a-z-]+\z/
  }
  @kind_format ~r/\A[a-z_]+\z/
  @anchor_kinds ~w(node edge point)
  @override_id ~r/\Apn:[0-9]+\z/
  @override_actions ~w(retain suppress)

  @type t :: %{String.t() => term}

  def format_version, do: @format_version

  def empty,
    do: %{
      "format_version" => @format_version,
      "locations" => [],
      "connections" => [],
      "closures" => [],
      "playable_overrides" => []
    }

  @doc "Generates an id for a new object, e.g. `new_id(\"locations\")` -> `\"loc:3f2a…\"`."
  def new_id(collection) when is_map_key(@id_formats, collection) do
    prefix = %{"locations" => "loc", "connections" => "conn", "closures" => "clo"}[collection]
    "#{prefix}:#{Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)}"
  end

  # --- Loading and saving -------------------------------------------------------------

  @doc "Reads and validates `authored.json` in a world directory. Returns the document and its content hash."
  @spec load(Path.t()) :: {:ok, t, String.t()} | {:error, [String.t()]}
  def load(dir) do
    path = Path.join(dir, "authored.json")

    with {:ok, text} <- read(path),
         {:ok, data} <- decode(text),
         {:ok, doc} <- validate(data) do
      {:ok, doc, hash(text)}
    end
  end

  @doc """
  Saves a document if `authored.json` still has `base_hash` (the hash from `load/1`). Returns the new hash.
  Another writer having changed the file in the meantime is a `:conflict`; nothing is overwritten.
  """
  @spec save(Path.t(), t, String.t()) ::
          {:ok, String.t()} | {:error, :conflict | [String.t()] | term}
  def save(dir, doc, base_hash) do
    path = Path.join(dir, "authored.json")

    with {:ok, doc} <- validate(doc),
         {:ok, current} <- read(path),
         :ok <- if(hash(current) == base_hash, do: :ok, else: {:error, :conflict}) do
      text = encode(doc)
      temp = path <> ".tmp"

      with :ok <- File.write(temp, text), :ok <- File.rename(temp, path) do
        {:ok, hash(text)}
      end
    end
  end

  @doc "Deterministic pretty JSON: sorted keys, collections ordered by id, trailing newline."
  def encode(doc) do
    sorted =
      Enum.reduce(~w(locations connections closures playable_overrides), doc, fn key, acc ->
        Map.update(acc, key, [], fn list -> Enum.sort_by(list, & &1["id"]) end)
      end)

    Jason.encode!(ordered(sorted), pretty: true) <> "\n"
  end

  def hash(text), do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)

  defp ordered(map) when is_map(map) do
    map
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {k, v} -> {k, ordered(v)} end)
    |> Jason.OrderedObject.new()
  end

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(other), do: other

  defp read(path) do
    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, reason} -> {:error, ["authored.json: cannot read (#{reason})"]}
    end
  end

  defp decode(text) do
    case Jason.decode(text) do
      {:ok, data} ->
        {:ok, data}

      {:error, %Jason.DecodeError{} = e} ->
        {:error, ["authored.json: invalid JSON (#{Exception.message(e)})"]}
    end
  end

  # --- Validation ---------------------------------------------------------------------

  @doc "Validates structure and internal references. Returns the document with defaults filled, or all error messages."
  @spec validate(term) :: {:ok, t} | {:error, [String.t()]}
  def validate(data) when is_map(data) do
    errors =
      check_keys(
        data,
        ~w(format_version locations connections closures),
        ~w(playable_overrides),
        "document"
      ) ++
        version_errors(data) ++
        Enum.flat_map(~w(locations connections closures), &collection_errors(data, &1)) ++
        override_errors(data)

    errors = errors ++ internal_reference_errors(data, errors)

    if errors == [], do: {:ok, normalize(data)}, else: {:error, errors}
  end

  def validate(_), do: {:error, ["document: must be a JSON object"]}

  defp override_errors(%{"playable_overrides" => list}) when is_list(list) do
    ids = for o <- list, is_map(o), is_binary(o["id"]), do: o["id"]

    list
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {o, i} when is_map(o) ->
        path = "playable_overrides[#{i}]"

        check_keys(o, ~w(id action), [], path) ++
          if(is_binary(o["id"]) and Regex.match?(@override_id, o["id"]),
            do: [],
            else: ["#{path}.id: must look like \"pn:<number>\""]
          ) ++
          if(o["action"] in @override_actions,
            do: [],
            else: ["#{path}.action: must be one of #{Enum.join(@override_actions, ", ")}"]
          )

      {_, i} ->
        ["playable_overrides[#{i}]: must be an object"]
    end)
    |> Kernel.++(
      for {id, n} <- Enum.frequencies(ids),
          n > 1,
          do: "playable_overrides: duplicate id #{inspect(id)}"
    )
  end

  defp override_errors(%{"playable_overrides" => _}), do: ["playable_overrides: must be a list"]
  defp override_errors(_), do: []

  defp version_errors(%{"format_version" => @format_version}), do: []

  defp version_errors(%{"format_version" => v}),
    do: [
      "format_version: unsupported version #{inspect(v)} (this editor reads #{@format_version})"
    ]

  defp version_errors(_), do: ["format_version: missing"]

  defp collection_errors(data, name) do
    case Map.get(data, name) do
      list when is_list(list) ->
        list
        |> Enum.with_index()
        |> Enum.flat_map(fn {item, i} -> item_errors(name, item, "#{name}[#{i}]") end)
        |> Kernel.++(duplicate_ids(name, list))

      _ ->
        ["#{name}: must be a list"]
    end
  end

  defp duplicate_ids(name, list) do
    list
    |> Enum.map(&(is_map(&1) && &1["id"]))
    |> Enum.filter(&is_binary/1)
    |> Enum.frequencies()
    |> Enum.filter(fn {_, n} -> n > 1 end)
    |> Enum.map(fn {id, _} -> "#{name}: duplicate id #{inspect(id)}" end)
  end

  defp item_errors(_name, item, path) when not is_map(item), do: ["#{path}: must be an object"]

  defp item_errors("locations", loc, path) do
    check_keys(loc, ~w(id name anchor), ~w(notes), path) ++
      id_errors("locations", loc, path) ++
      string_errors(loc, "name", path) ++
      string_errors(loc, "notes", path, optional: true) ++
      anchor_errors(loc["anchor"], path <> ".anchor")
  end

  defp item_errors("connections", conn, path) do
    check_keys(conn, ~w(id from to kind), ~w(notes geometry), path) ++
      id_errors("connections", conn, path) ++
      kind_errors(conn, path) ++
      string_errors(conn, "notes", path, optional: true) ++
      Enum.flat_map(~w(from to), fn key ->
        if is_binary(conn[key]) and Regex.match?(@id_formats["locations"], conn[key]),
          do: [],
          else: ["#{path}.#{key}: must be a location id"]
      end) ++
      if(conn["from"] != nil and conn["from"] == conn["to"],
        do: ["#{path}: from and to must be different locations"],
        else: []
      ) ++
      geometry_errors(conn, path)
  end

  defp item_errors("closures", clo, path) do
    check_keys(clo, ~w(id edge kind geometry_hash), ~w(reason), path) ++
      id_errors("closures", clo, path) ++
      kind_errors(clo, path) ++
      string_errors(clo, "reason", path, optional: true) ++
      string_errors(clo, "geometry_hash", path) ++
      if(is_binary(clo["edge"]) and String.starts_with?(clo["edge"], "edge:"),
        do: [],
        else: ["#{path}.edge: must be an edge id"]
      )
  end

  # Connections are straight lines between their locations for now; custom geometry is reserved.
  defp geometry_errors(%{"geometry" => nil}, _), do: []

  defp geometry_errors(%{"geometry" => _}, path),
    do: ["#{path}.geometry: not supported yet (must be null)"]

  defp geometry_errors(_, _), do: []

  defp anchor_errors(%{"kind" => kind} = anchor, path) when kind in @anchor_kinds do
    case kind do
      "point" ->
        check_keys(anchor, ~w(kind point), [], path) ++
          point_errors(anchor["point"], path <> ".point")

      "node" ->
        check_keys(anchor, ~w(kind ref point), [], path) ++
          ref_errors(anchor["ref"], "node:", path) ++
          point_errors(anchor["point"], path <> ".point")

      "edge" ->
        check_keys(anchor, ~w(kind ref offset point ref_geometry_hash), [], path) ++
          ref_errors(anchor["ref"], "edge:", path) ++
          point_errors(anchor["point"], path <> ".point") ++
          offset_errors(anchor["offset"], path) ++
          string_errors(anchor, "ref_geometry_hash", path)
    end
  end

  defp anchor_errors(%{"kind" => kind}, path),
    do: ["#{path}.kind: #{inspect(kind)} is not one of #{Enum.join(@anchor_kinds, ", ")}"]

  defp anchor_errors(anchor, path) when is_map(anchor), do: ["#{path}.kind: missing"]
  defp anchor_errors(_, path), do: ["#{path}: must be an object"]

  defp ref_errors(ref, prefix, path) do
    if is_binary(ref) and String.starts_with?(ref, prefix),
      do: [],
      else: ["#{path}.ref: must be a #{String.trim_trailing(prefix, ":")} id"]
  end

  defp offset_errors(offset, path) do
    if is_number(offset) and offset >= 0 and offset <= 1,
      do: [],
      else: ["#{path}.offset: must be a number between 0 and 1"]
  end

  defp point_errors([lon, lat], path) when is_number(lon) and is_number(lat) do
    if lon >= -180 and lon <= 180 and lat >= -90 and lat <= 90,
      do: [],
      else: point_errors(nil, path)
  end

  defp point_errors(_, path), do: ["#{path}: must be [longitude, latitude]"]

  defp id_errors(name, item, path) do
    if is_binary(item["id"]) and Regex.match?(@id_formats[name], item["id"]),
      do: [],
      else: ["#{path}.id: must look like #{inspect(prefix(name))}<letters-or-digits>"]
  end

  defp prefix("locations"), do: "loc:"
  defp prefix("connections"), do: "conn:"
  defp prefix("closures"), do: "clo:"

  defp kind_errors(item, path) do
    if is_binary(item["kind"]) and Regex.match?(@kind_format, item["kind"]),
      do: [],
      else: ["#{path}.kind: must be lowercase letters and underscores"]
  end

  defp string_errors(item, key, path, opts \\ []) do
    case Map.fetch(item, key) do
      {:ok, v} when is_binary(v) -> []
      :error -> if opts[:optional], do: [], else: ["#{path}.#{key}: missing"]
      _ -> ["#{path}.#{key}: must be a string"]
    end
  end

  defp check_keys(item, required, optional, path) when is_map(item) do
    keys = Map.keys(item)
    missing = for k <- required, not Map.has_key?(item, k), do: "#{path}: missing #{inspect(k)}"

    unknown =
      for k <- keys,
          k not in required,
          k not in optional,
          do: "#{path}: unknown key #{inspect(k)}"

    missing ++ unknown
  end

  defp check_keys(_, _, _, _), do: []

  # Connections must point at locations that exist. Skipped when the structure is already broken.
  defp internal_reference_errors(_data, [_ | _]), do: []

  defp internal_reference_errors(data, []) do
    ids = MapSet.new(data["locations"], & &1["id"])

    for {conn, i} <- Enum.with_index(data["connections"]),
        key <- ~w(from to),
        conn[key] not in ids do
      "connections[#{i}].#{key}: no location #{inspect(conn[key])}"
    end
  end

  defp normalize(data) do
    data
    |> Map.put_new("playable_overrides", [])
    |> Map.update!("locations", fn list -> Enum.map(list, &Map.put_new(&1, "notes", "")) end)
    |> Map.update!("connections", fn list ->
      Enum.map(list, fn c -> c |> Map.put_new("notes", "") |> Map.put_new("geometry", nil) end)
    end)
    |> Map.update!("closures", fn list -> Enum.map(list, &Map.put_new(&1, "reason", "")) end)
  end
end
