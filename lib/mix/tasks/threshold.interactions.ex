defmodule Mix.Tasks.Threshold.Interactions do
  @shortdoc "Validates a world's interactions.json and reports problems"
  @moduledoc """
  Read-only: `mix threshold.interactions [world]`.

  Validates `interactions.json` (strictly) and lints it against `authored.json`: missing or
  unwalkable places, interactions that can never become available, and discoveries that are never
  granted or never used. It writes nothing. A world without the file reports zero interactions.
  Exits with an error if the file is invalid; warnings do not fail it. To check a copy, point
  `THRESHOLD_WORLDS_DIR` at it.
  """
  use Mix.Task

  alias Threshold.{Authored, Interactions}

  @requirements ["app.config"]

  @impl true
  def run(args) do
    name = List.first(args) || Threshold.World.default_name()

    with {:ok, dir} <- Threshold.World.dir(name),
         {:ok, authored, _} <- Authored.load(dir),
         {:ok, doc, hash} <- Interactions.load(dir) do
      warnings = Interactions.lint(doc, authored)

      Mix.shell().info(
        [
          "Interactions for #{name} (read-only)",
          "File: #{if hash, do: "interactions.json (#{String.slice(hash, 0, 12)})", else: "none"}",
          "#{length(doc["interactions"])} interactions, #{length(doc["discoveries"])} discoveries, #{length(warnings)} warnings"
          | Enum.map(warnings, &"  #{&1.kind}: #{&1.message}")
        ]
        |> Enum.join("\n")
      )
    else
      {:error, errors} when is_list(errors) ->
        Mix.raise("Cannot check #{name}:\n  " <> Enum.join(errors, "\n  "))

      other ->
        Mix.raise("Cannot check #{name}: #{inspect(other)}")
    end
  end
end
