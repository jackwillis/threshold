defmodule Threshold.Generated do
  @moduledoc """
  The generated geography of a world (`nodes`, `edges`, `context`, `provenance`, `playable`) as
  immutable snapshots.

  Each publication copies the five files into `generations/<id>/` (the id is a digest of their
  content) and then repoints the `generated` symlink with one atomic rename. A reader resolves
  `active/1` once and reads every file from that snapshot directory, so it never observes a mix
  of old and new files, and a failed publication leaves the previous snapshot active.

  A plain `generated/` directory (the pipeline's CLI output, test fixtures) is also readable; the
  first publication converts it into a snapshot. The CLI writes into whatever `generated`
  resolves to, so running it while the app serves that world is a development convenience only.
  """

  @files ~w(nodes.geojson edges.geojson context.geojson provenance.json playable.json)
  @keep 3
  @id ~r/\A[0-9a-f]{12}\z/

  @type snapshot :: %{dir: Path.t(), generation: String.t()}

  def files, do: @files

  @doc "The snapshot currently published for a world directory."
  @spec active(Path.t()) :: {:ok, snapshot} | :error
  def active(world_dir) do
    link = Path.join(world_dir, "generated")

    case File.read_link(link) do
      {:ok, target} ->
        dir = Path.expand(target, world_dir)
        if File.dir?(dir), do: {:ok, %{dir: dir, generation: Path.basename(dir)}}, else: :error

      {:error, _} ->
        if File.dir?(link), do: {:ok, %{dir: link, generation: "working"}}, else: :error
    end
  end

  @doc "A specific snapshot, for a browser that must keep reading the revision it started with."
  @spec snapshot(Path.t(), String.t() | nil) :: {:ok, snapshot} | :error
  def snapshot(world_dir, nil), do: active(world_dir)

  def snapshot(_world_dir, generation) when not is_binary(generation), do: :error

  def snapshot(world_dir, generation) do
    with {:ok, active} <- active(world_dir) do
      dir = Path.join([world_dir, "generations", generation])

      cond do
        generation == active.generation ->
          {:ok, active}

        Regex.match?(@id, generation) and File.dir?(dir) ->
          {:ok, %{dir: dir, generation: generation}}

        true ->
          :error
      end
    end
  end

  @doc """
  Publishes the generated files in `source` as the world's active snapshot. Callers hold
  `Threshold.WorldFile.locked/2`. Returns the new generation id.
  """
  @spec publish(Path.t(), Path.t()) :: {:ok, String.t()} | {:error, String.t()}
  def publish(world_dir, source) do
    case Enum.reject(@files, &File.regular?(Path.join(source, &1))) do
      [] -> do_publish(world_dir, source)
      missing -> {:error, "Cannot publish: missing generated #{Enum.join(missing, ", ")}."}
    end
  end

  defp do_publish(world_dir, source) do
    id = digest(source)
    generations = Path.join(world_dir, "generations")
    destination = Path.join(generations, id)
    staging = Path.join(generations, ".staging-#{System.unique_integer([:positive])}")
    link = Path.join(world_dir, ".generated-#{System.unique_integer([:positive])}")

    try do
      File.mkdir_p!(staging)
      for file <- @files, do: File.cp!(Path.join(source, file), Path.join(staging, file))
      install(staging, destination, id, world_dir)
      adopt_plain_directory(world_dir)
      File.ln_s!(Path.join("generations", id), link)
      File.rename!(link, Path.join(world_dir, "generated"))
      prune(generations, id)
      {:ok, id}
    rescue
      error -> {:error, "Could not publish generated files: #{Exception.message(error)}"}
    after
      File.rm_rf(staging)
      File.rm(link)
    end
  end

  # An existing snapshot with this id is reused when its content matches (a rebuild with
  # identical output); a corrupt or hand-modified one is replaced unless it is the active one.
  defp install(staging, destination, id, world_dir) do
    cond do
      not File.exists?(destination) ->
        File.rename!(staging, destination)

      digest(destination) == id ->
        :ok

      match?({:ok, %{generation: ^id}}, active(world_dir)) ->
        raise "active snapshot #{id} does not match its content"

      true ->
        File.rm_rf!(destination)
        File.rename!(staging, destination)
    end
  end

  # One-time conversion of a plain `generated/` directory so the symlink can replace it.
  defp adopt_plain_directory(world_dir) do
    path = Path.join(world_dir, "generated")

    with {:error, :einval} <- File.read_link(path),
         true <- File.dir?(path) do
      legacy = Path.join([world_dir, "generations", digest(path)])
      if File.exists?(legacy), do: File.rm_rf!(path), else: File.rename!(path, legacy)
    end

    :ok
  end

  defp prune(generations, active_id) do
    stale =
      generations
      |> File.ls!()
      |> Enum.filter(&(Regex.match?(@id, &1) and &1 != active_id))
      |> Enum.sort_by(&File.stat!(Path.join(generations, &1), time: :posix).mtime, :desc)
      |> Enum.drop(@keep - 1)

    for id <- stale, do: File.rm_rf(Path.join(generations, id))
    :ok
  end

  @doc "Twelve hex characters identifying the content of a directory of generated files."
  @spec digest(Path.t()) :: String.t()
  def digest(dir) do
    @files
    |> Enum.map(fn file -> [file, 0, File.read!(Path.join(dir, file))] end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end
end
