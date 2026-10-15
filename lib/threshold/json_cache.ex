defmodule Threshold.JsonCache do
  @moduledoc """
  Decodes large, immutable JSON documents (generated geography) once per distinct content.

  Entries are keyed by the SHA-256 of the text, so a changed file can never return a stale
  document, and only the few most recently decoded documents are kept. Callers still read the
  file and hash it each time, which keeps their revision tied to the exact bytes they used; only
  the expensive decode is skipped.
  """
  @spec decode(binary) :: {:ok, term} | {:error, Jason.DecodeError.t()}
  def decode(text) when is_binary(text) do
    Threshold.BoundedCache.fetch(:json_documents, :crypto.hash(:sha256, text), fn ->
      Jason.decode(text)
    end)
  end

  @doc "Returns a derived result from its own bounded cache, separate from decoded documents."
  @spec memo(term, (-> term)) :: term
  def memo(key, fun) do
    {:ok, value} = Threshold.BoundedCache.fetch(:json_derived, key, fn -> {:ok, fun.()} end)
    value
  end
end
