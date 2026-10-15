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
    cached = Threshold.BoundedCache.entries(:json_documents)
    assert length(cached) <= 4
    # An evicted document is simply decoded again.
    assert {:ok, %{"n" => 1}} = JsonCache.decode(List.first(texts))
  end

  test "concurrent distinct inserts stay within each independent window" do
    1..400
    |> Task.async_stream(fn n -> JsonCache.memo({:concurrent, n}, fn -> n end) end,
      max_concurrency: 100,
      timeout: :infinity
    )
    |> Enum.each(fn {:ok, n} -> assert is_integer(n) end)

    assert length(Threshold.BoundedCache.entries(:json_derived)) == 4
  end

  test "many distinct bounding boxes cannot evict a decoded document" do
    text = ~s({"document":"kept"})
    assert {:ok, document} = JsonCache.decode(text)
    for n <- 1..100, do: JsonCache.memo({:bbox, n}, fn -> n end)
    hash = :crypto.hash(:sha256, text)
    assert {{:json_documents, hash}, document} in Threshold.BoundedCache.entries(:json_documents)
  end
end
