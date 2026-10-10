defmodule Threshold.GameNumberingTest do
  use ExUnit.Case, async: true
  alias Threshold.Game
  alias Threshold.Game.{Geometry, Player, World}

  @origin [-89.4, 43.07]

  # A world whose centre location "c" has one neighbour per `{id, dx, dy}` offset (degrees).
  defp star(neighbours) do
    point = fn dx, dy -> [Enum.at(@origin, 0) + dx, Enum.at(@origin, 1) + dy] end

    locations =
      Map.new(
        [{"c", %{"id" => "c", "point" => @origin}}] ++
          for({id, dx, dy} <- neighbours, do: {id, %{"id" => id, "point" => point.(dx, dy)}})
      )

    connections =
      Map.new(neighbours, fn {id, dx, dy} ->
        geometry = %{"type" => "LineString", "coordinates" => [@origin, point.(dx, dy)]}

        {"pc:#{id}",
         %{
           "id" => "pc:#{id}",
           "from" => "c",
           "to" => id,
           "length_m" => 10,
           "geometry" => geometry
         }}
      end)

    %World{name: "star", locations: locations, connections: connections}
  end

  defp numbered(neighbours),
    do:
      star(neighbours)
      |> Game.numbered_moves(%Player{location: "c"})
      |> Enum.map(&{&1.key, &1.destination})

  describe "Geometry.bearing/2" do
    test "is clockwise from north in [0, 360)" do
      assert_in_delta Geometry.bearing(@origin, [-89.4, 43.08]), 0, 1.0e-9
      assert_in_delta Geometry.bearing(@origin, [-89.39, 43.07]), 90, 1.0e-6
      assert_in_delta Geometry.bearing(@origin, [-89.4, 43.06]), 180, 1.0e-9
      assert_in_delta Geometry.bearing(@origin, [-89.41, 43.07]), 270, 1.0e-6
      assert Geometry.bearing(@origin, [-89.4000001, 43.08]) > 359.9
    end

    test "accounts for longitude shrinking with latitude" do
      # At 43 degrees N a degree of longitude is about 0.73 of a degree of latitude.
      dx = 0.01 / :math.cos(43.07 * :math.pi() / 180)
      assert_in_delta Geometry.bearing(@origin, [-89.4 + dx, 43.07 + 0.01]), 45, 0.01
    end
  end

  describe "Game.numbered_moves/2" do
    test "orders a four-way intersection north, east, south, west regardless of ids" do
      # Alphabetical id order is the reverse of radial order here.
      assert [{"1", "d-north"}, {"2", "c-east"}, {"3", "b-south"}, {"4", "a-west"}] ==
               numbered([
                 {"a-west", -0.001, 0},
                 {"b-south", 0, -0.001},
                 {"c-east", 0.001, 0},
                 {"d-north", 0, 0.001}
               ])
    end

    test "handles irregular bearings and starts at north, not at the first id" do
      assert [{"1", "ne"}, {"2", "ese"}, {"3", "s"}, {"4", "wsw"}, {"5", "nnw"}] ==
               numbered([
                 {"nnw", -0.0002, 0.001},
                 {"wsw", -0.001, -0.0003},
                 {"s", 0.0001, -0.001},
                 {"ese", 0.001, -0.0002},
                 {"ne", 0.0007, 0.0007}
               ])
    end

    test "a destination just west of north comes last, just east of north first" do
      assert [{"1", "east-of-north"}, {"2", "south"}, {"3", "west-of-north"}] ==
               numbered([
                 {"west-of-north", -0.00001, 0.001},
                 {"south", 0, -0.001},
                 {"east-of-north", 0.00001, 0.001}
               ])
    end

    test "equal bearings are ordered by destination id" do
      assert [{"1", "a-far"}, {"2", "b-near"}] ==
               numbered([{"a-far", 0.002, 0}, {"b-near", 0.001, 0}])

      assert numbered([{"a-far", 0.002, 0}, {"b-near", 0.001, 0}]) ==
               numbered([{"b-near", 0.001, 0}, {"a-far", 0.002, 0}])
    end

    test "assigns 1-9 then 0 to ten moves and leaves the rest unnumbered but present" do
      neighbours =
        for i <- 0..11,
            do:
              {"p#{String.pad_leading("#{i}", 2, "0")}",
               :math.sin(i * 30 * :math.pi() / 180) * 0.001,
               :math.cos(i * 30 * :math.pi() / 180) * 0.001}

      moves = numbered(neighbours)
      assert length(moves) == 12
      assert Enum.map(moves, &elem(&1, 0)) == ~w(1 2 3 4 5 6 7 8 9 0) ++ [nil, nil]

      assert Enum.map(moves, &elem(&1, 1)) ==
               Enum.map(0..11, &"p#{String.pad_leading("#{&1}", 2, "0")}")
    end

    test "has the same moves as available_moves, and moving uses the destination id" do
      world = star([{"a", 0, 0.001}, {"b", 0.001, 0}])
      player = %Player{location: "c", visited: MapSet.new(["c"])}

      assert Enum.sort(Enum.map(Game.numbered_moves(world, player), & &1.destination)) ==
               Enum.map(Game.available_moves(world, player), & &1.destination)

      assert {:ok, %{location: "b", turn: 1}, _} = Game.move(world, player, "b")
    end
  end
end
