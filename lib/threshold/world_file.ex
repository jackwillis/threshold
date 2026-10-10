defmodule Threshold.WorldFile do
  @moduledoc """
  Serializes writes to a world directory and replaces files atomically.

  The lock is per directory and covers a whole check-then-write sequence (compare the content
  hash, write, rename), so competing writers cannot both pass the check from the same base
  revision. It is node-local, which matches the single-node, file-based design.
  """

  @doc "Runs `fun` while holding the write lock for the world directory `dir`."
  @spec locked(Path.t(), (-> result)) :: result when result: term
  def locked(dir, fun) do
    :global.trans({{__MODULE__, Path.expand(dir)}, self()}, fun, [node()], :infinity)
  end

  @doc "Writes `text` to a unique temporary file beside `path`, then renames it over `path`."
  @spec write_atomic(Path.t(), iodata) :: :ok | {:error, term}
  def write_atomic(path, text) do
    temp = "#{path}.#{System.unique_integer([:positive])}.tmp"

    with :ok <- File.write(temp, text),
         :ok <- File.rename(temp, path) do
      :ok
    else
      error ->
        File.rm(temp)
        error
    end
  end
end
