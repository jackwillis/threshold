defmodule Threshold.Importer do
  @moduledoc """
  Runs the Python importer (`gis/`) as a subprocess.

  Only `build`, `playable` and `validate` are exposed. `acquire` contacts OpenStreetMap and
  must stay an explicit command-line action. The command is configurable so tests
  can substitute a stub: `config :threshold, Threshold.Importer, command: {exe, args}`.
  """
  require Logger

  @commands ~w(build playable validate)
  @timeout :timer.minutes(5)

  @type result :: {:ok, String.t()} | {:error, String.t()}

  @spec run(String.t(), String.t()) :: result
  def run(command, world, root \\ Threshold.World.root()) when command in @commands do
    if Regex.match?(~r/\A[a-z0-9-]+\z/i, world) do
      {exe, args} = executable()
      Logger.info("importer #{command} #{world}")

      task =
        Task.async(fn ->
          System.cmd(
            exe,
            args ++ [command, world, "--worlds-dir", Path.expand(root)],
            stderr_to_stdout: true,
            cd: File.cwd!()
          )
        end)

      case Task.yield(task, @timeout) || Task.shutdown(task) do
        {:ok, {output, 0}} -> {:ok, output}
        {:ok, {output, status}} -> {:error, "importer exited #{status}\n" <> output}
        nil -> {:error, "importer timed out"}
      end
    else
      {:error, "invalid world name"}
    end
  end

  # Everything the pipeline reads. Generated files are rebuilt in the scratch copy and published
  # as one snapshot; nothing else is ever copied back.
  @pipeline_inputs ~w(config.json boundary.geojson authored.json source)

  @doc "Builds and validates a scratch copy offline, then publishes the generated files as one atomic snapshot."
  def regenerate(world) do
    if Threshold.World.valid_name?(world) do
      root = Path.expand(Threshold.World.root())
      :global.trans({{__MODULE__, root, world}, self()}, fn -> regenerate_copy(root, world) end)
    else
      {:error, "invalid world name"}
    end
  end

  defp regenerate_copy(root, world) do
    dir = Path.join(root, world)

    scratch =
      Path.join(System.tmp_dir!(), "threshold-build-#{System.unique_integer([:positive])}")

    try do
      before = inputs(dir)
      File.mkdir_p!(Path.join(scratch, world))

      for entry <- @pipeline_inputs,
          File.exists?(Path.join(dir, entry)),
          do: File.cp_r!(Path.join(dir, entry), Path.join([scratch, world, entry]))

      with {:ok, log} <- build_copy(world, scratch) do
        # Saves are held off while the inputs are re-checked and the files published, so an
        # input cannot change between the check and the publication.
        Threshold.WorldFile.locked(dir, fn -> publish(dir, scratch, world, before, log) end)
      end
    rescue
      error -> {:error, Exception.message(error)}
    after
      File.rm_rf(scratch)
    end
  end

  defp publish(dir, scratch, world, before, log) do
    if before == inputs(dir) do
      case Threshold.Generated.publish(dir, Path.join([scratch, world, "generated"])) do
        {:ok, _generation} -> {:ok, log}
        {:error, message} -> {:error, message}
      end
    else
      {:error,
       "World inputs changed during regeneration. No generated files were published; retry with current saved inputs."}
    end
  end

  defp inputs(dir) do
    for file <- [
          "config.json",
          "boundary.geojson",
          "authored.json" | Path.wildcard(Path.join(dir, "source/**/*"))
        ],
        path = if(Path.type(file) == :absolute, do: file, else: Path.join(dir, file)),
        File.regular?(path),
        into: %{} do
      {path, :crypto.hash(:sha256, File.read!(path))}
    end
  end

  defp build_copy(world, root) do
    Enum.reduce_while(~w(build playable validate), {:ok, ""}, fn command, {:ok, log} ->
      case run(command, world, root) do
        {:ok, output} -> {:cont, {:ok, log <> "#{command}:\n" <> output}}
        {:error, output} -> {:halt, {:error, log <> "#{command}:\n" <> output}}
      end
    end)
  end

  defp executable do
    case Application.get_env(:threshold, __MODULE__, [])[:command] do
      nil -> {Path.expand(".venv/bin/threshold-gis"), []}
      command -> command
    end
  end
end
