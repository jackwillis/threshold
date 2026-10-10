defmodule Threshold.JsonCache do
  @moduledoc """
  Decodes large, immutable JSON documents (generated geography) once per distinct content.

  Entries are keyed by the SHA-256 of the text, so a changed file can never return a stale
  document, and only the few most recently decoded documents are kept. Callers still read the
  file and hash it each time, which keeps their revision tied to the exact bytes they used; only
  the expensive decode is skipped.
  """
  @keep 4
  @index {__MODULE__, :index}

  @spec decode(binary) :: {:ok, term} | {:error, Jason.DecodeError.t()}
  def decode(text) when is_binary(text) do
    key = {__MODULE__, :crypto.hash(:sha256, text)}

    case :persistent_term.get(key, nil) do
      nil ->
        with {:ok, document} <- Jason.decode(text) do
          remember(key, document)
          {:ok, document}
        end

      document ->
        {:ok, document}
    end
  end

  @doc """
  Returns the cached result for `key`, computing it with `fun` on first use. Shares the same
  small recency window as `decode/1`, so derived results (such as a clipped layer) expire with it.
  """
  @spec memo(term, (-> term)) :: term
  def memo(key, fun) do
    full = {__MODULE__, :memo, key}

    case :persistent_term.get(full, nil) do
      nil ->
        value = fun.()
        remember(full, value)
        value

      value ->
        value
    end
  end

  defp remember(key, document) do
    recent = [key | List.delete(:persistent_term.get(@index, []), key)]
    {keep, drop} = Enum.split(recent, @keep)
    :persistent_term.put(key, document)
    :persistent_term.put(@index, keep)
    for old <- drop, do: :persistent_term.erase(old)
    :ok
  end
end
