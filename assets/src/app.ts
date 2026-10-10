import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { MapEditor } from "./hooks/map_editor";

import { PlayerMap } from "./hooks/player_map";
import { AtlasPrototype } from "./hooks/atlas_prototype";

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { MapEditor, PlayerMap, AtlasPrototype },
});

// A server-side `push_event(socket, "restore-focus", %{to: selector})` moves focus to `to`, but only if
// focus was lost (the focused element was removed by the patch). Focus the user placed is never stolen.
window.addEventListener("phx:restore-focus", (event) => {
  const target = document.querySelector<HTMLElement>((event as CustomEvent<{ to: string }>).detail.to);
  const active = document.activeElement;
  if (target && (!active || active === document.body || !active.isConnected)) target.focus();
});

liveSocket.connect();
(window as unknown as { liveSocket: unknown }).liveSocket = liveSocket;
