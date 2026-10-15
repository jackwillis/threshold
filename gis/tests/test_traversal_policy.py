"""Keep pipeline core eligibility in step with the runtime street-access policy."""

import re
from pathlib import Path

from threshold_gis.playable import ACCESS, VEHICLE_SERVICE


def test_runtime_policy_parity():
    source = (Path(__file__).resolve().parents[2] / "lib/threshold/traversal.ex").read_text()
    for attribute, values in (("access", ACCESS), ("vehicle_service", VEHICLE_SERVICE)):
        match = re.search(rf"@{attribute}\s+~w\(([^)]*)\)", source)
        assert match, f"Cannot read Elixir traversal @{attribute}; update the parity test with the policy representation"
        assert set(match.group(1).split()) == values
