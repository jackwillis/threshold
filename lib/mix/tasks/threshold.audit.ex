defmodule Mix.Tasks.Threshold.Audit do
  @shortdoc "Reports how authored places and connections relate to the playable network"
  @moduledoc """
  Read-only attachment audit: `mix threshold.audit [world] [--details]`.

  Reads the world's `authored.json` and generated geography and prints a report. It writes
  nothing. To audit a copy instead of the real world, point `THRESHOLD_WORLDS_DIR` at it.
  """
  use Mix.Task

  alias Threshold.{Authored, AttachmentAudit}
  alias Threshold.Game.World

  @requirements ["app.config"]

  @impl true
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: [details: :boolean])
    name = List.first(rest) || Threshold.World.default_name()

    with {:ok, world} <- World.load(name),
         {:ok, dir} <- Threshold.World.dir(name),
         {:ok, authored, _hash} <- Authored.load(dir) do
      report = AttachmentAudit.audit(authored, world)
      Mix.shell().info(format(name, report, opts[:details] || false))
    else
      error -> Mix.raise("Cannot audit #{name}: #{inspect(error)}")
    end
  end

  defp format(name, %{summary: s, places: places, connections: connections}, details?) do
    head = [
      "Attachment audit for #{name} (read-only)",
      "Playable locations: #{s.playable_locations}; default spawn: #{s.default_spawn || "none"}",
      "",
      "Places: #{s.places}  #{inspect(s.by_status)}",
      "  unattached with a source-edge suggestion: #{s.unattached_with_edge_suggestion}",
      "  unattached and ambiguous (top two candidates about equally close): #{s.unattached_ambiguous}",
      "  unattached and disconnected (no candidate, or not reachable from the default spawn): #{s.unattached_disconnected}",
      "Connections: #{s.connections}  by kind #{inspect(s.connections_by_kind)}",
      "  by walking comparison #{inspect(s.connections_by_class)}"
    ]

    detail =
      if details? do
        ["", "Places:"] ++
          for p <- places do
            suggestion =
              p.suggestion &&
                "#{p.suggestion.id} #{p.suggestion.distance_m} m via #{p.suggestion.via}"

            "  #{p.id} #{inspect(p.name)} #{p.status} #{inspect(p.flags)} -> #{suggestion || "no candidate"}"
          end ++
          ["", "Connections:"] ++
          for c <- connections do
            "  #{c.id} #{c.kind} straight #{c.straight_m} m, walk #{inspect(c.walk_m)} m, #{c.class}"
          end
      else
        []
      end

    Enum.join(head ++ detail, "\n")
  end
end
