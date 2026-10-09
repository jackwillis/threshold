defmodule Threshold.Importer do
  @moduledoc """
  Runs the Python importer (`gis/`) as a subprocess.

  Only `build` and `validate` are exposed. `acquire` contacts OpenStreetMap and
  must stay an explicit command-line action. The command is configurable so tests
  can substitute a stub: `config :threshold, Threshold.Importer, command: {exe, args}`.
  """
  require Logger

  @commands ~w(build validate)
  @timeout :timer.minutes(5)

  @type result :: {:ok, String.t()} | {:error, String.t()}

  @spec run(String.t(), String.t()) :: result
  def run(command, world) when command in @commands do
    if Regex.match?(~r/\A[a-z0-9-]+\z/i, world) do
      {exe, args} = executable()
      Logger.info("importer #{command} #{world}")

      task =
        Task.async(fn ->
          System.cmd(exe, args ++ [command, world], stderr_to_stdout: true, cd: File.cwd!())
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

  defp executable do
    case Application.get_env(:threshold, __MODULE__, [])[:command] do
      nil -> {Path.expand(".venv/bin/threshold-gis"), []}
      command -> command
    end
  end
end
