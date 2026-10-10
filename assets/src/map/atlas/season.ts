import type { Map as MapLibreMap } from "maplibre-gl";
import type { Treatment } from "./materials";
import { applySeason } from "./style";
import { SEASONS, SEASON_TOKENS, cssVariables, type Season } from "./tokens";

// Season is a display preference only: it repaints the map and sets CSS variables. It is never sent to
// the server, never saved with progress, and nothing in movement, numbering or camera reads it.
const STORAGE_KEY = "threshold.season";

export const isSeason = (value: unknown): value is Season => SEASONS.includes(value as Season);

/** `?season=` wins, then the remembered choice, then summer. Storage may be blocked; that is fine. */
export function initialSeason(search = location.search): Season {
  const asked = new URLSearchParams(search).get("season");
  if (isSeason(asked)) return asked;
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (isSeason(stored)) return stored;
  } catch { /* storage unavailable */ }
  return "summer";
}

/** Sets the --atlas-* variables on `el` and the pressed state of its `[data-season]` buttons. */
export function paintPage(el: HTMLElement, season: Season): void {
  for (const [name, value] of Object.entries(cssVariables(SEASON_TOKENS[season]))) el.style.setProperty(name, value);
  el.dataset.activeSeason = season;
  el.querySelectorAll<HTMLButtonElement>("[data-season]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.season === season)));
}

/** Wires the season buttons inside `el` to repaint `map` in place. Returns a function that detaches them. */
export function bindSeasonButtons(el: HTMLElement, map: MapLibreMap, onChange?: (season: Season) => void, treatment: Treatment = "subtle"): () => void {
  const listeners: [HTMLButtonElement, () => void][] = [];
  el.querySelectorAll<HTMLButtonElement>("[data-season]").forEach((button) => {
    const listener = () => {
      const season = button.dataset.season;
      if (!isSeason(season)) return;
      applySeason(map, SEASON_TOKENS[season], treatment);
      paintPage(el, season);
      try { localStorage.setItem(STORAGE_KEY, season); } catch { /* storage unavailable */ }
      const url = new URL(location.href);
      url.searchParams.set("season", season);
      history.replaceState(history.state, "", url);
      onChange?.(season);
    };
    button.addEventListener("click", listener);
    listeners.push([button, listener]);
  });
  return () => listeners.forEach(([button, listener]) => button.removeEventListener("click", listener));
}
