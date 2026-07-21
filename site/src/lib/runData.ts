/*
 * Authentic run data. Scores, layer scores, and critique wording are verbatim
 * from the app's own review.json files (run 20260721-175550-dropped and the
 * gallery runs). The only edit is typographic: em dashes in the judge's prose
 * are rendered as hyphens. Never fabricate or round these numbers.
 */

export interface LayerScores {
  componentStructure: number;
  formDetail: number;
  materialSurface: number;
  silhouetteProportion: number;
}

export interface Cycle {
  n: number;
  model: string; // path under /models
  overall: number;
  layers: LayerScores;
  action: string;
  critique: string;
  best?: boolean;
}

// iPhone run - the timeline centerpiece. A real, verifiable climb:
// 0.45 -> 0.68 -> 0.72, and the exported model.glb is byte-identical to cycle 3.
export const TIMELINE_SUBJECT =
  "A pastel-lilac flagship phone: silver aluminium rails, matte glass back, a dual-camera pill bump, and a purple-blue radial flower wallpaper.";

export const timelineCycles: Cycle[] = [
  {
    n: 1,
    model: "/models/iphone-cycle-1.glb",
    overall: 0.45,
    layers: {
      componentStructure: 0.55,
      formDetail: 0.4,
      materialSurface: 0.4,
      silhouetteProportion: 0.5,
    },
    action: "refine-code",
    critique:
      "The 'rear wallpaper glow' emissive plane is oversized or offset in world space: in the front and three-quarter renders, purple beam/petal geometry protrudes far beyond the phone's silhouette left and right, breaking the outer contour - the wallpaper must be clamped to the display area (0.47 x 0.97) and drawn as a flat emissive texture on the screen surface, not as 3D petals floating off the body. Body proportions, corner rounding, and pill Dynamic Island read correctly. Frame rails read dark gray/black instead of light silver anodized aluminum (#D8D4E0); raise baseColor brightness and check lighting. Screen emissive bloom at the flower center is far too intense (blown-out white hotspot); reduce emissive intensity so the radial petal gradient reads.",
  },
  {
    n: 2,
    model: "/models/iphone-cycle-2.glb",
    overall: 0.68,
    layers: {
      componentStructure: 0.7,
      formDetail: 0.62,
      materialSurface: 0.6,
      silhouetteProportion: 0.78,
    },
    action: "refine-code",
    critique:
      "Silhouette and aspect ratio are close: rounded-corner slab, correct width/height/depth feel, and the camera bump protrudes correctly in side/top views. Fixes: (1) Frame rails read dark charcoal gray instead of light silver anodized aluminum (#D8D4E0, metalness 0.9) - brighten the rail albedo and increase environment reflection so the perimeter band reads metallic silver. (2) The wallpaper is a crude 8-petal asterisk of uniform capsules; the reference shows layered translucent petals with a bright center bloom fading to pale lilac edges - rebuild as stacked, opacity-graded petal planes plus an emissive radial gradient underlay. (3) The black bezel ring is too thin to read at the corners; widen slightly and match corner radius to body. (4) Side buttons appear as tiny nubs; elongate them into flush pills matching the frame.",
  },
  {
    n: 3,
    model: "/models/iphone.glb",
    overall: 0.72,
    layers: {
      componentStructure: 0.7,
      formDetail: 0.68,
      materialSurface: 0.65,
      silhouetteProportion: 0.82,
    },
    action: "refine-code",
    best: true,
    critique:
      "Silhouette and proportions are solid: tall slab, rounded corners, thin depth read correctly in all four views, and the top view confirms the raised pill camera bump with lenses. Front face matches well: edge-to-edge screen, thin black bezel, pill-shaped Dynamic Island at top, radial purple flower wallpaper. Biggest remaining mismatch: the frame/side rails still render dark where the reference shows bright silver anodized aluminum - raise the frame material's albedo toward #D8D4E0 and lower roughness so it reads as light metal. Corner radius looks slightly tight in front view - soften toward the reference's larger radius. This was the top-scoring cycle, so it is the one Maquette kept and exported.",
  },
];

export interface GalleryItem {
  id: string;
  name: string;
  subtitle: string;
  model: string;
  usdz: string;
  poster: string;
  glbBytes: number;
}

// Gallery - real exported models from real runs.
export const gallery: GalleryItem[] = [
  {
    id: "iphone",
    name: "Lilac phone",
    subtitle: "3 cycles, judged to 0.72",
    model: "/models/iphone.glb",
    usdz: "/models/iphone.usdz",
    poster: "/img/poster-iphone.png",
    glbBytes: 311992,
  },
  {
    id: "earbuds",
    name: "Earbuds case",
    subtitle: "Accepted at 0.78 in one cycle",
    model: "/models/earbuds.glb",
    usdz: "/models/earbuds.usdz",
    poster: "/img/poster-earbuds.png",
    glbBytes: 59028,
  },
  {
    id: "chest",
    name: "Treasure chest",
    subtitle: "Sculpted from a single photo",
    model: "/models/chest.glb",
    usdz: "/models/chest.usdz",
    poster: "/img/poster-chest.png",
    glbBytes: 29056,
  },
];

// Hero model - the MacBook Air run's final export.
export const HERO_MODEL = "/models/macbook-air.glb";

// Juxtapose - the iPhone run: source photo vs the app's own front render.
export const JUXTAPOSE = {
  photo: "/img/iphone-ref.jpg",
  render: "/img/iphone-render.png",
};
