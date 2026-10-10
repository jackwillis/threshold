defmodule Threshold.BoundaryTest do
  use ExUnit.Case, async: true

  alias Threshold.Boundary

  @moduletag :tmp_dir

  @square [[-89.39, 43.07], [-89.37, 43.07], [-89.37, 43.08], [-89.39, 43.08], [-89.39, 43.07]]
  @config %{"buffer_m" => 250}

  describe "polygon/1" do
    test "accepts a closed ring and closes an open one" do
      assert {:ok, %{"type" => "Polygon", "coordinates" => [@square]}} = Boundary.polygon(@square)
      assert {:ok, %{"coordinates" => [@square]}} = Boundary.polygon(Enum.drop(@square, -1))
    end

    test "rejects too few corners, flat shapes, bad positions and self-intersections" do
      assert {:error, "A boundary needs at least three" <> _} = Boundary.polygon([[0, 0], [1, 1]])

      assert {:error, "A boundary cannot be flat."} =
               Boundary.polygon([[0, 0], [1, 1], [2, 2], [0, 0]])

      assert {:error, "Boundary positions" <> _} =
               Boundary.polygon([[0, 0], [1, 1], [999, 2], [0, 0]])

      assert {:error, "Boundary must be a list" <> _} = Boundary.polygon("nope")

      bowtie = [[0, 0], [2, 2], [2, 0], [0, 2], [0, 0]]
      assert {:error, "The boundary edges cross each other."} = Boundary.polygon(bowtie)
    end

    test "a non-rectangular simple polygon is fine" do
      l_shape = [[0, 0], [2, 0], [2, 1], [1, 1], [1, 2], [0, 2], [0, 0]]
      assert {:ok, _} = Boundary.polygon(l_shape)
    end
  end

  describe "coverage_error/3" do
    # Snapshot built from the square plus 250 m (about 0.0023 deg lat, 0.0031 deg lon).
    @manifest %{"bounds" => [-89.3935, 43.0677, -89.3665, 43.0823]}

    test "no manifest means nothing to check" do
      {:ok, geometry} = Boundary.polygon(@square)
      assert nil == Boundary.coverage_error(geometry, @config, nil)
    end

    test "a boundary inside the snapshot's reach is allowed" do
      {:ok, geometry} = Boundary.polygon(@square)
      assert nil == Boundary.coverage_error(geometry, @config, @manifest)
    end

    test "the original Madison boundary passes against the real snapshot bounds" do
      original = [
        [-89.391777, 43.06993],
        [-89.369448, 43.06993],
        [-89.369448, 43.080139],
        [-89.391777, 43.080139],
        [-89.391777, 43.06993]
      ]

      manifest = %{
        "bounds" => [-89.3948467307057, 43.06767978522409, -89.3663782390292, 43.08238921027942]
      }

      {:ok, geometry} = Boundary.polygon(original)
      assert nil == Boundary.coverage_error(geometry, @config, manifest)
    end

    test "growing past the snapshot is refused with guidance" do
      {:ok, geometry} =
        Boundary.polygon([[-89.40, 43.07], [-89.37, 43.07], [-89.37, 43.08], [-89.40, 43.08]])

      assert Boundary.coverage_error(geometry, @config, @manifest) =~ "make acquire-world"
    end
  end

  describe "coverage_error/3 with an explicit import area" do
    @import_manifest %{"bounds" => [-89.40, 43.06, -89.35, 43.09]}
    @import_config %{"buffer_m" => 250, "import_bounds" => [-89.40, 43.06, -89.35, 43.09]}

    test "a boundary anywhere inside the import area is allowed, with no buffer required" do
      edge = [
        [-89.399, 43.061],
        [-89.351, 43.061],
        [-89.351, 43.089],
        [-89.399, 43.089],
        [-89.399, 43.061]
      ]

      {:ok, geometry} = Boundary.polygon(edge)
      assert Boundary.coverage_error(geometry, @import_config, @import_manifest) == nil
    end

    test "a boundary beyond the import area is refused" do
      {:ok, geometry} =
        Boundary.polygon([[-89.41, 43.07], [-89.36, 43.07], [-89.36, 43.08], [-89.41, 43.08]])

      assert Boundary.coverage_error(geometry, @import_config, @import_manifest) =~
               "beyond the import area"
    end
  end

  describe "save/4" do
    setup %{tmp_dir: dir} do
      File.mkdir_p!(Path.join(dir, "source"))
      File.write!(Path.join(dir, "source/manifest.json"), Jason.encode!(@manifest))

      File.write!(
        Path.join(dir, "boundary.geojson"),
        ~s({"type":"Feature","properties":{"name":"Playable boundary"},"geometry":{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,0]]]}})
      )

      %{hash: Boundary.hash(File.read!(Path.join(dir, "boundary.geojson")))}
    end

    test "writes the geometry, keeps existing properties and returns the new hash", %{
      tmp_dir: dir,
      hash: hash
    } do
      {:ok, geometry} = Boundary.polygon(@square)
      assert {:ok, new_hash} = Boundary.save(dir, geometry, hash, @config)

      saved = dir |> Path.join("boundary.geojson") |> File.read!()
      assert new_hash == Boundary.hash(saved)

      assert %{"properties" => %{"name" => "Playable boundary"}, "geometry" => ^geometry} =
               Jason.decode!(saved)

      refute File.exists?(Path.join(dir, "boundary.geojson.tmp"))
    end

    test "refuses to overwrite a file that changed since it was loaded", %{tmp_dir: dir} do
      {:ok, geometry} = Boundary.polygon(@square)
      before = File.read!(Path.join(dir, "boundary.geojson"))
      assert {:error, :conflict} = Boundary.save(dir, geometry, "stale-hash", @config)
      assert File.read!(Path.join(dir, "boundary.geojson")) == before
    end

    test "refuses a boundary beyond snapshot coverage", %{tmp_dir: dir, hash: hash} do
      {:ok, geometry} =
        Boundary.polygon([[-89.5, 43.0], [-89.0, 43.0], [-89.0, 43.5], [-89.5, 43.5]])

      assert {:error, "That boundary plus" <> _} = Boundary.save(dir, geometry, hash, @config)
    end

    test "competing saves from one base revision: exactly one wins, the rest conflict", %{
      tmp_dir: dir,
      hash: hash
    } do
      results =
        1..8
        |> Enum.map(fn writer ->
          ring =
            for k <- 0..20_000 do
              angle = 2 * :math.pi() * rem(k, 20_000) / 20_000

              [
                -89.38 + 0.001 * writer * :math.cos(angle),
                43.075 + 0.001 * writer * :math.sin(angle)
              ]
            end

          geometry = %{"type" => "Polygon", "coordinates" => [ring]}
          Task.async(fn -> Boundary.save(dir, geometry, hash, @config) end)
        end)
        |> Task.await_many(60_000)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :conflict})) == 7

      assert Path.wildcard(Path.join(dir, "boundary.geojson*")) == [
               Path.join(dir, "boundary.geojson")
             ]
    end
  end
end
