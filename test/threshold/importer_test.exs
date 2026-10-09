defmodule Threshold.ImporterTest do
  use ExUnit.Case, async: false

  alias Threshold.Importer

  setup do
    previous = Application.get_env(:threshold, Importer)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:threshold, Importer, previous),
        else: Application.delete_env(:threshold, Importer)
    end)
  end

  test "returns output on success" do
    Application.put_env(:threshold, Importer, command: {"echo", ["stub"]})
    assert {:ok, output} = Importer.run("build", "tiny")
    assert output == "stub build tiny --worlds-dir #{Path.expand(Threshold.World.root())}\n"
  end

  test "regenerates offline in order" do
    Application.put_env(:threshold, Importer, command: {"echo", []})
    assert {:ok, output} = Importer.regenerate("tiny")
    assert output =~ "build:\nbuild tiny --worlds-dir"
    assert output =~ "playable:\nplayable tiny --worlds-dir"
    assert output =~ "validate:\nvalidate tiny --worlds-dir"
    refute output =~ "acquire"
  end

  test "returns the error with output on a nonzero exit" do
    Application.put_env(:threshold, Importer, command: {"sh", ["-c", "echo boom; exit 3"]})
    assert {:error, "importer exited 3\nboom\n"} = Importer.run("build", "madison")
  end

  test "rejects unsafe world names" do
    assert {:error, "invalid world name"} = Importer.run("build", "../etc")
  end

  test "does not expose acquire" do
    assert_raise FunctionClauseError, fn -> Importer.run("acquire", "madison") end
  end
end
