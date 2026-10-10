defmodule Threshold.Interactions do
  @moduledoc """
  Authored gameplay interactions (`interactions.json`): short investigations attached to authored
  places. See `docs/gameplay-interactions.md`.

    * An **interaction** belongs to one place and may require discoveries before it is offered.
    * Its **scene** is plain presentation (a title and paragraphs); there is no scene chaining.
    * A **choice** completes the interaction and may grant **discoveries**. Discoveries are declared
      ids, so a typo is an error rather than a new silent fact.

  This module is pure: it reads, validates, lints and encodes the file, and never touches the
  database or the authored world. A world without `interactions.json` simply has none. Validation
  is strict (unknown keys are errors) like `Threshold.Authored`; references to places in
  `authored.json` are checked by `lint/2` and reported, never repaired.
  """

  alias Threshold.Authored

  @format_version 1
  @discovery_id ~r/\Adisc:[0-9a-z-]+\z/
  @interaction_id ~r/\Aint:[0-9a-z-]+\z/
  @place_id ~r/\Aloc:[0-9a-z-]+\z/
  @choice_id ~r/\A[0-9a-z-]+\z/

  @type t :: %{String.t() => term}
  @type warning :: %{kind: atom, id: String.t(), message: String.t()}

  def format_version, do: @format_version

  def empty, do: %{"format_version" => @format_version, "discoveries" => [], "interactions" => []}

  # --- Loading ------------------------------------------------------------------------

  @doc """
  Reads and validates a world's `interactions.json`. Returns the document and its content hash;
  an absent file is the empty document with a `nil` hash.
  """
  @spec load(Path.t()) :: {:ok, t, String.t() | nil} | {:error, [String.t()]}
  def load(dir) do
    case File.read(Path.join(dir, "interactions.json")) do
      {:ok, text} -> parse(text)
      {:error, :enoent} -> {:ok, empty(), nil}
      {:error, reason} -> {:error, ["interactions.json: cannot read (#{reason})"]}
    end
  end

  @spec parse(String.t()) :: {:ok, t, String.t()} | {:error, [String.t()]}
  def parse(text) do
    with {:ok, data} <- decode(text),
         {:ok, doc} <- validate(data) do
      {:ok, doc, Authored.hash(text)}
    end
  end

  defp decode(text) do
    case Jason.decode(text) do
      {:ok, data} -> {:ok, data}
      {:error, e} -> {:error, ["interactions.json: invalid JSON (#{Exception.message(e)})"]}
    end
  end

  @doc "Deterministic pretty JSON: sorted keys, collections ordered by id; bodies and choices keep their order."
  def encode(doc) do
    sorted =
      doc
      |> Map.update("discoveries", [], &Enum.sort_by(&1, fn d -> d["id"] end))
      |> Map.update("interactions", [], &Enum.sort_by(&1, fn i -> i["id"] end))

    Jason.encode!(Authored.ordered(sorted), pretty: true) <> "\n"
  end

  # --- Read model ---------------------------------------------------------------------

  @doc """
  The interactions the panel offers for the player's current place. `state` is the player's
  `%{discovered: MapSet, completed: MapSet}` (see `Threshold.Game.Sessions.interaction_state/1`).
  An interaction is `:available` when every required discovery has been made, `:completed` once
  finished (listed, not actionable), and **absent** while its requirements are unmet, so nothing
  hints at it. Only interactions at the player's place appear. Pure; the server re-checks all of
  this inside the completion transaction, so this list is presentation, never authority.
  """
  @spec at(t, Threshold.Game.World.t(), Threshold.Game.Player.t(), %{
          discovered: MapSet.t(),
          completed: MapSet.t()
        }) ::
          [%{interaction: map, status: :available | :completed}]
  def at(content, world, player, %{discovered: discovered, completed: completed}) do
    for i <- Enum.sort_by(content["interactions"], & &1["id"]),
        Threshold.Game.at_place?(world, player, i["place"]),
        status = status(i, discovered, completed),
        do: %{interaction: i, status: status}
  end

  defp status(i, discovered, completed) do
    cond do
      MapSet.member?(completed, i["id"]) -> :completed
      Enum.all?(i["requires"], &MapSet.member?(discovered, &1)) -> :available
      true -> nil
    end
  end

  # --- Validation (structure and internal references) ----------------------------------

  @spec validate(term) :: {:ok, t} | {:error, [String.t()]}
  def validate(data) when is_map(data) do
    errors =
      keys(data, ~w(format_version discoveries interactions), [], "document") ++
        version_errors(data) ++
        list_errors(data, "discoveries", &discovery_errors/2) ++
        list_errors(data, "interactions", &interaction_errors/2)

    errors = errors ++ reference_errors(data, errors)
    if errors == [], do: {:ok, data}, else: {:error, errors}
  end

  def validate(_), do: {:error, ["document: must be a JSON object"]}

  defp version_errors(%{"format_version" => @format_version}), do: []

  defp version_errors(%{"format_version" => v}),
    do: ["format_version: unsupported version #{inspect(v)} (expected #{@format_version})"]

  defp version_errors(_), do: []

  defp list_errors(data, name, each) do
    case Map.get(data, name) do
      list when is_list(list) ->
        list
        |> Enum.with_index()
        |> Enum.flat_map(fn {item, i} -> each.(item, "#{name}[#{i}]") end)
        |> Kernel.++(duplicate_ids(name, list))

      nil ->
        []

      _ ->
        ["#{name}: must be a list"]
    end
  end

  defp discovery_errors(d, path) when is_map(d) do
    keys(d, ~w(id label), [], path) ++
      id_error(d["id"], @discovery_id, "disc:<letters-digits-dashes>", path) ++
      text_error(d["label"], "#{path}.label")
  end

  defp discovery_errors(_, path), do: ["#{path}: must be an object"]

  defp interaction_errors(i, path) when is_map(i) do
    keys(i, ~w(id place title requires scene choices), [], path) ++
      id_error(i["id"], @interaction_id, "int:<letters-digits-dashes>", path) ++
      id_error(i["place"], @place_id, "an authored location id (loc:...)", path, "place") ++
      text_error(i["title"], "#{path}.title") ++
      id_list_errors(i["requires"], "#{path}.requires") ++
      scene_errors(i["scene"], "#{path}.scene") ++
      choices_errors(i["choices"], "#{path}.choices")
  end

  defp interaction_errors(_, path), do: ["#{path}: must be an object"]

  defp scene_errors(%{} = scene, path) do
    keys(scene, ~w(title body), [], path) ++
      text_error(scene["title"], "#{path}.title") ++
      case scene["body"] do
        [_ | _] = body ->
          for {p, n} <- Enum.with_index(body),
              not (is_binary(p) and String.trim(p) != ""),
              do: "#{path}.body[#{n}]: must be non-empty text"

        _ ->
          ["#{path}.body: must be a non-empty list of paragraphs"]
      end
  end

  defp scene_errors(_, path), do: ["#{path}: must be an object"]

  defp choices_errors([_ | _] = choices, path) do
    ids = for %{"id" => id} <- choices, is_binary(id), do: id

    Enum.flat_map(Enum.with_index(choices), fn
      {%{} = c, n} ->
        p = "#{path}[#{n}]"

        keys(c, ~w(id label discovers), [], p) ++
          id_error(c["id"], @choice_id, "letters, digits and dashes", p) ++
          text_error(c["label"], "#{p}.label") ++
          id_list_errors(c["discovers"], "#{p}.discovers")

      {_, n} ->
        ["#{path}[#{n}]: must be an object"]
    end) ++
      for {id, count} <- Enum.frequencies(ids),
          count > 1,
          do: "#{path}: duplicate choice id #{inspect(id)}"
  end

  defp choices_errors(_, path),
    do: ["#{path}: must be a non-empty list (a read-only scene uses one choice)"]

  defp id_list_errors(list, path) when is_list(list) do
    bad =
      for {v, n} <- Enum.with_index(list),
          not is_binary(v),
          do: "#{path}[#{n}]: must be a discovery id"

    dup =
      for {v, c} <- Enum.frequencies(Enum.filter(list, &is_binary/1)),
          c > 1,
          do: "#{path}: duplicate #{inspect(v)}"

    bad ++ dup
  end

  defp id_list_errors(_, path), do: ["#{path}: must be a list of discovery ids"]

  # Every discovery named by `requires` or `discovers` must be declared. Skipped when the structure
  # is already broken, so one typo does not produce a flood.
  defp reference_errors(_data, [_ | _]), do: []

  defp reference_errors(data, []) do
    declared = MapSet.new(data["discoveries"], & &1["id"])

    for {i, n} <- Enum.with_index(data["interactions"]),
        {field, id, where} <- discovery_refs(i, n),
        id not in declared do
      "#{where}.#{field}: #{inspect(id)} is not a declared discovery"
    end
  end

  defp discovery_refs(i, n) do
    requires = for id <- i["requires"], do: {"requires", id, "interactions[#{n}]"}

    discovers =
      for {c, k} <- Enum.with_index(i["choices"]),
          id <- c["discovers"],
          do: {"discovers", id, "interactions[#{n}].choices[#{k}]"}

    requires ++ discovers
  end

  defp duplicate_ids(name, list) do
    for {id, count} <- Enum.frequencies(for %{"id" => id} <- list, is_binary(id), do: id),
        count > 1,
        do: "#{name}: duplicate id #{inspect(id)}"
  end

  defp id_error(value, format, expected, path, field \\ "id") do
    if is_binary(value) and Regex.match?(format, value),
      do: [],
      else: ["#{path}.#{field}: must be #{expected}"]
  end

  defp text_error(value, path),
    do:
      if(is_binary(value) and String.trim(value) != "",
        do: [],
        else: ["#{path}: must be non-empty text"]
      )

  defp keys(item, required, optional, path) when is_map(item) do
    missing = for k <- required, not Map.has_key?(item, k), do: "#{path}: missing #{inspect(k)}"

    unknown =
      for k <- Map.keys(item),
          k not in required,
          k not in optional,
          do: "#{path}: unknown key #{inspect(k)}"

    missing ++ unknown
  end

  # --- Lint (semantic checks; reported, never repaired) --------------------------------

  @doc """
  Problems that do not stop the file loading but would make play confusing:

    * `:missing_place` - the interaction's place is not in `authored.json`
    * `:unwalkable_place` - the place is a free point with no walking `access`, so nobody can reach it
    * `:unreachable_interaction` - it can never become available (it needs a discovery nothing can
      grant first, including circular requirements)
    * `:undiscoverable_discovery` / `:unused_discovery` - declared but granted by no choice / required by nothing
  """
  @spec lint(t, Authored.t()) :: [warning]
  def lint(doc, authored) do
    places = Map.new(authored["locations"], &{&1["id"], &1})

    place_warnings =
      for i <- doc["interactions"] do
        case places[i["place"]] do
          nil ->
            warn(
              :missing_place,
              i["id"],
              "#{i["id"]} is attached to #{i["place"]}, which is not in authored.json"
            )

          %{"anchor" => %{"kind" => "point"}, "access" => _} ->
            nil

          %{"anchor" => %{"kind" => "point"}} ->
            warn(
              :unwalkable_place,
              i["id"],
              "#{i["id"]} is at #{i["place"]}, a free point with no walking access"
            )

          _ ->
            nil
        end
      end

    reachable = reachable_interactions(doc)

    unreachable =
      for i <- doc["interactions"],
          i["id"] not in reachable,
          do:
            warn(
              :unreachable_interaction,
              i["id"],
              "#{i["id"]} can never become available: its required discoveries cannot be obtained first"
            )

    granted =
      MapSet.new(for i <- doc["interactions"], c <- i["choices"], d <- c["discovers"], do: d)

    required = MapSet.new(for i <- doc["interactions"], d <- i["requires"], do: d)

    discovery_warnings =
      for %{"id" => id} <- doc["discoveries"] do
        cond do
          id not in granted ->
            warn(:undiscoverable_discovery, id, "#{id} is declared but no choice grants it")

          id not in required ->
            warn(:unused_discovery, id, "#{id} is granted but nothing requires it")

          true ->
            nil
        end
      end

    Enum.reject(place_warnings ++ unreachable ++ discovery_warnings, &is_nil/1)
  end

  defp warn(kind, id, message), do: %{kind: kind, id: id, message: message}

  # Fixpoint: an interaction is reachable once everything it requires can be granted by a reachable one.
  defp reachable_interactions(doc), do: grow(doc["interactions"], MapSet.new(), MapSet.new())

  defp grow(interactions, reachable, discovered) do
    {now, _} =
      Enum.split_with(
        interactions,
        &(&1["id"] not in reachable and Enum.all?(&1["requires"], fn d -> d in discovered end))
      )

    if now == [] do
      reachable
    else
      grants = for i <- now, c <- i["choices"], d <- c["discovers"], do: d
      grow(interactions, Enum.into(now, reachable, & &1["id"]), Enum.into(grants, discovered))
    end
  end
end
