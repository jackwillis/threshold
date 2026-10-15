defmodule Threshold.TraversalTest do
  use ExUnit.Case, async: true
  alias Threshold.Traversal

  test "accepted access statuses allow pedestrian ways and alleys" do
    for access <- ~w(public unknown conditional mixed), service <- [nil, "alley"] do
      assert :ok =
               Traversal.walkable?(
                 %{"access_status" => access, "service" => service},
                 MapSet.new()
               )
    end
  end

  test "restricted or unknown statuses and vehicle services are blocked" do
    for access <- [nil, "restricted", "future"] do
      assert {:blocked, :access} = Traversal.walkable?(%{"access_status" => access}, MapSet.new())
    end

    for service <- ~w(driveway parking_aisle drive-through emergency_access) do
      assert {:blocked, :access} =
               Traversal.walkable?(
                 %{"access_status" => "public", "service" => service},
                 MapSet.new()
               )
    end
  end

  test "restricted closures take precedence over access restrictions" do
    assert {:blocked, :closure} =
             Traversal.walkable?(
               %{"id" => "e:1", "access_status" => "restricted"},
               MapSet.new(["e:1"])
             )
  end
end
