defmodule Mix.Tasks.Threshold.Routes do
  @shortdoc "Resolves authored connections to real walks over the street network (read-only)"
  @moduledoc """
  `mix threshold.routes [world] [--details]`

  Reports, for the world's authored places, whether each sits on an intersection, near one, or
  halfway down a block, and whether each authored connection resolves to a walk under the
  game's traversal rules. It writes nothing. Point `THRESHOLD_WORLDS_DIR` at a copy to audit a
  copy instead of the real world.
  """
  use Mix.Task

  alias Threshold.{Authored, RouteResolver}

  @requirements ["app.config"]

  @impl true
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: [details: :boolean])
    name = List.first(rest) || Threshold.World.default_name()

    with {:ok, world} <- Threshold.World.load(name),
         generated when is_binary(generated) <- world.generated,
         {:ok, authored, _hash} <- Authored.load(world.dir),
         {:ok, edges} <- read(generated, "edges.geojson"),
         {:ok, playable} <- read(generated, "playable.json") do
      to_playable = Map.new(playable["locations"], &{&1["node"], &1["id"]})
      report = RouteResolver.resolve(authored, edges["features"], to_playable)
      Mix.shell().info(format(name, report, opts[:details] || false))
    else
      error -> Mix.raise("Cannot resolve routes for #{name}: #{inspect(error)}")
    end
  end

  defp read(dir, file) do
    with {:ok, text} <- File.read(Path.join(dir, file)), do: Jason.decode(text)
  end

  defp format(name, %{summary: s, places: places, connections: connections}, details?) do
    head = [
      "Route resolution for #{name} (read-only)",
      "Places: #{s.places}  #{inspect(s.places_by_class)}; #{s.places_on_playable_location} coincide with a generated playable location",
      "Connections: #{s.connections}  #{inspect(s.connections_by_status)}; long detours: #{s.detours}",
      "  blocking rules on blocked routes: #{inspect(s.blocker_reasons)}"
    ]

    detail =
      if details? do
        ["", "Places:"] ++
          for p <- places do
            extra = [
              p[:playable] && "= #{p.playable}",
              p[:snap_m] && "#{p.snap_m} m from #{p.node}",
              p[:nearest_edge] && "nearest street #{inspect(p.nearest_edge)}"
            ]

            "  #{p.id} #{inspect(p.name)} #{p.class} #{Enum.reject(extra, &(!&1)) |> Enum.join(" ")}"
          end ++
          ["", "Connections:"] ++
          for c <- connections do
            blockers =
              if c.blockers == [],
                do: "",
                else:
                  " blocked by " <> Enum.map_join(c.blockers, ", ", &"#{&1.reason}(#{&1.edge})")

            "  #{c.id} #{c.status} straight #{c.straight_m} m, walk #{inspect(c.path_m)} m#{if c.detour, do: " DETOUR", else: ""}#{blockers}#{if c.note, do: " " <> c.note, else: ""}"
          end
      else
        []
      end

    Enum.join(head ++ detail, "\n")
  end
end
