defmodule Threshold.ImporterTest do
  use ExUnit.Case, async: false

  alias Threshold.Importer

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    previous_root = Application.get_env(:threshold, :worlds_dir)
    File.cp_r!(Path.join(Threshold.World.root(), "tiny"), Path.join(tmp, "tiny"))
    Application.put_env(:threshold, :worlds_dir, tmp)
    previous = Application.get_env(:threshold, Importer)

    on_exit(fn ->
      Application.put_env(:threshold, :worlds_dir, previous_root)

      if previous,
        do: Application.put_env(:threshold, Importer, previous),
        else: Application.delete_env(:threshold, Importer)
    end)

    %{dir: Path.join(tmp, "tiny")}
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

  test "a playable failure does not publish the successful geography build", %{dir: dir} do
    before = File.read!(Path.join(dir, "edges.geojson"))

    script =
      ~s(if [ "$1" = build ]; then printf changed > "$4/$2/edges.geojson"; else echo failed; exit 3; fi)

    Application.put_env(:threshold, Importer, command: {"sh", ["-c", script, "--"]})
    assert {:error, output} = Importer.regenerate("tiny")
    assert output =~ "playable:"
    refute output =~ "validate:"
    assert File.read!(Path.join(dir, "edges.geojson")) == before
    refute File.exists?(Path.join(dir, "edges.geojson.regenerating"))
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
