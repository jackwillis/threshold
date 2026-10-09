import maplibregl from "maplibre-gl";
import {
  TerraDraw,
  TerraDrawPointMode,
  TerraDrawLineStringMode,
  TerraDrawRectangleMode,
  TerraDrawSelectMode,
} from "terra-draw";
import { TerraDrawMapLibreGLAdapter } from "terra-draw-maplibre-gl-adapter";

// No basemap by design (offline, and the game world's extent stays obvious): a plain background only.
const BLANK_STYLE: maplibregl.StyleSpecification = {
  version: 8,
  sources: {},
  layers: [{ id: "background", type: "background", paint: { "background-color": "#f4f1ea" } }],
};

// Madison study area centre; the viewer will fit to the boundary once data loads.
const CENTER: [number, number] = [-89.3806, 43.075];

type HookContext = { el: HTMLElement; map?: maplibregl.Map; draw?: TerraDraw };

export const MapEditor = {
  mounted(this: HookContext) {
    const map = new maplibregl.Map({
      container: this.el,
      style: BLANK_STYLE,
      center: CENTER,
      zoom: 15,
      attributionControl: { customAttribution: "© OpenStreetMap contributors" },
    });
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }));

    const draw = new TerraDraw({
      adapter: new TerraDrawMapLibreGLAdapter({ map }),
      modes: [
        new TerraDrawSelectMode(),
        new TerraDrawPointMode(),
        new TerraDrawLineStringMode(),
        new TerraDrawRectangleMode(),
      ],
    });
    map.on("load", () => draw.start());

    this.map = map;
    this.draw = draw;
  },

  destroyed(this: HookContext) {
    this.draw?.stop();
    this.map?.remove();
  },
};
