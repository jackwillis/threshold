defmodule Threshold.JsonCacheTest do
  use ExUnit.Case, async: false
  alias Threshold.JsonCache

  test "decodes, reuses by content and never returns a stale document" do
    assert {:ok, %{"a" => 1}} = JsonCache.decode(~s({"a":1}))
    assert {:ok, %{"a" => 1}} = JsonCache.decode(~s({"a":1}))
    assert {:ok, %{"a" => 2}} = JsonCache.decode(~s({"a":2}))
    assert {:error, %Jason.DecodeError{}} = JsonCache.decode("{broken")
  end

  test "keeps only the most recent documents" do
    texts = for n <- 1..8, do: ~s({"n":#{n}})
    for text <- texts, do: JsonCache.decode(text)
    cached = for {{JsonCache, hash}, _} <- :persistent_term.get(), is_binary(hash), do: hash
    assert length(cached) <= 4
    # An evicted document is simply decoded again.
    assert {:ok, %{"n" => 1}} = JsonCache.decode(List.first(texts))
  end
end
