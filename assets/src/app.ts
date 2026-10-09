import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { MapEditor } from "./hooks/map_editor";

import { PlayerMap } from "./hooks/player_map";

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { MapEditor, PlayerMap },
});

liveSocket.connect();
(window as unknown as { liveSocket: unknown }).liveSocket = liveSocket;
