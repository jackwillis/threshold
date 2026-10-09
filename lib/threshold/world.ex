defmodule Threshold.World do
  @moduledoc """
  Reads a world directory (`priv/worlds/<name>`): imported geography, config, boundary,
  provenance and the authored layer. This module never writes imported files.
  """

  @layers ~w(boundary provenance nodes edges context authored playable)
  @name_format ~r/\A[a-z0-9-]+\z/i

  @type staleness :: :fresh | :missing | {:stale, [String.t()]}

  @doc "Layers that may be served to the browser."
  def layers, do: @layers

  def valid_name?(name), do: is_binary(name) and Regex.match?(@name_format, name)

  def default_name, do: Application.get_env(:threshold, :default_world, "madison")

  def root,
    do:
      Application.get_env(:threshold, :worlds_dir) ||
        Path.join(:code.priv_dir(:threshold), "worlds")

  def dir(name) when is_binary(name) do
    if valid_name?(name), do: {:ok, Path.join(root(), name)}, else: :error
  end

  @doc "Path of a servable layer file, or `:error` for unknown worlds, layers or missing files."
  def layer_path(name, layer) when layer in @layers do
    with {:ok, dir} <- dir(name),
         path = Path.join(dir, filename(layer)),
         true <- File.regular?(path) do
      {:ok, path}
    else
      _ -> :error
    end
  end

  def layer_path(_name, _layer), do: :error

  defp filename("boundary"), do: "boundary.geojson"
  defp filename("provenance"), do: "provenance.json"
  defp filename("authored"), do: "authored.json"
  defp filename("playable"), do: "playable.json"
  defp filename(layer), do: layer <> ".geojson"

  @doc """
  Loads the small files the editor shell needs. Large geography stays on disk and is
  fetched by the browser.
  """
  def load(name) do
    with {:ok, dir} <- dir(name),
         {:ok, config} <- read_json(Path.join(dir, "config.json")),
         {:ok, boundary_text} <- File.read(Path.join(dir, "boundary.geojson")),
         {:ok, boundary} <- Jason.decode(boundary_text) do
      provenance =
        case read_json(Path.join(dir, "provenance.json")) do
          {:ok, data} -> data
          _ -> nil
        end

      {:ok,
       %{
         name: name,
         dir: dir,
         config: config,
         boundary: boundary,
         boundary_hash: Threshold.Boundary.hash(boundary_text),
         provenance: provenance,
         staleness: staleness(dir, config, boundary, provenance)
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Compares what the generated geography was built from with the files on disk. Editing the
  boundary, changing the config or replacing the snapshot makes the geography stale.
  """
  @spec staleness(Path.t(), map, map, map | nil) :: staleness
  def staleness(_dir, _config, _boundary, nil), do: :missing

  def staleness(dir, config, boundary, provenance) do
    reasons =
      Enum.reject(
        [
          provenance["config"] != config &&
            "Import configuration changed since the geography was built.",
          provenance["boundary"] != boundary["geometry"] &&
            "Boundary changed since the geography was built.",
          source_changed?(dir, provenance) &&
            "Source snapshot differs from the one the geography was built from."
        ],
        &(&1 == false)
      )

    if reasons == [], do: :fresh, else: {:stale, reasons}
  end

  defp source_changed?(dir, provenance) do
    case read_json(Path.join(dir, "source/manifest.json")) do
      {:ok, manifest} -> manifest["sha256"] != get_in(provenance, ["source", "sha256"])
      _ -> true
    end
  end

  defp read_json(path) do
    with {:ok, text} <- File.read(path), do: Jason.decode(text)
  end
end
