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

  @generated ~w(nodes.geojson edges.geojson context.geojson provenance.json playable.json)

  @doc "Builds and validates a scratch copy offline before publishing generated files only."
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
      File.mkdir_p!(scratch)
      File.cp_r!(dir, Path.join(scratch, world))

      with {:ok, log} <- build_copy(world, scratch),
           true <- before == inputs(dir) do
        # Never copy authored.json, the boundary, configuration or source back.
        for file <- @generated do
          destination = Path.join(dir, file)
          temporary = destination <> ".regenerating"
          File.cp!(Path.join([scratch, world, file]), temporary)
        end

        for file <- @generated do
          destination = Path.join(dir, file)
          File.rename!(destination <> ".regenerating", destination)
        end

        {:ok, log}
      else
        false ->
          {:error,
           "World inputs changed during regeneration. No generated files were published; retry with current saved inputs."}

        error ->
          error
      end
    rescue
      error -> {:error, Exception.message(error)}
    after
      File.rm_rf(scratch)
      for file <- @generated, do: File.rm(Path.join(dir, file) <> ".regenerating")
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
