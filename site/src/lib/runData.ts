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
  "An iPhone 17 in pastel lilac: silver aluminum rails, matte glass back, a dual-camera pill bump, and a purple-blue radial flower wallpaper.";

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
      "The 'rear wallpaper glow' emissive plane is oversized or offset in world space: in the front and three-quarter renders, purple beam/petal geometry protrudes far beyond the phone's silhouette left and right, breaking the outer contour - the wallpaper must be clamped to the display area (0.47 x 0.97) and drawn as a flat emissive texture on the screen surface, not as 3D petals floating off the body. Body proportions, corner rounding, and pill Dynamic Island read correctly. The side view shows a camera bump and buttons, but no render shows the back panel directly, so the dual-lens pill bump, silver lens rings, flash dot, and rear logo cannot be verified - add a back view or rotate the three-quarter angle. Frame rails read dark gray/black in side and top views instead of light silver anodized aluminum (#D8D4E0); raise baseColor brightness and check lighting. Screen emissive bloom at the flower center is far too intense (blown-out white hotspot); reduce emissive intensity so the radial petal gradient reads. Verify side buttons are present on both rails (volume pair + power) as the spec requires.",
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
      "Silhouette and aspect ratio are close: rounded-corner slab, correct width/height/depth feel, and the camera bump protrudes correctly in side/top views. Fixes: (1) Frame rails read dark charcoal gray in side and threeQuarter views instead of light silver anodized aluminum (#D8D4E0, metalness 0.9) - brighten the rail albedo and increase environment reflection so the perimeter band reads metallic silver as in the reference. (2) The wallpaper is a crude 8-petal asterisk of uniform capsules; the reference shows layered translucent petals with a bright center bloom fading to pale lilac edges - rebuild as stacked, scaled, opacity-graded petal planes plus an emissive radial gradient underlay. (3) Dynamic Island pill is correct, but the black bezel ring is too thin to read at the corners; widen slightly and match corner radius to body. (4) No view clearly shows the back panel: verify the lilac matte back, centered subtle logo, flash dot right of the upper lens, and silver lens rims - the side render hints at lenses but rim/flash detail is unverifiable. (5) Side buttons appear as tiny nubs; elongate them into flush pills matching the frame per spec.",
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
      "Silhouette and proportions are solid: tall slab, rounded corners, thin depth read correctly in all four views, and the top view confirms the raised pill camera bump with lenses. Front face matches well: edge-to-edge screen, thin black bezel, pill-shaped Dynamic Island at top, radial purple flower wallpaper (though the render's petals are flatter and lower-contrast than the reference's layered translucent bloom - increase petal count/overlap and add a brighter emissive bloom at the convergence point). Biggest mismatch: the frame/side rails render nearly black in side and threeQuarter views where the reference shows bright silver anodized aluminum - raise the frame material's albedo toward #D8D4E0 and lower roughness so it reads as light metal, not dark plastic; the black bezel should stay black but the outer rail must not. No render shows the back panel directly, so the lilac matte back, camera bump plateau color, flash dot, and rear logo cannot be verified from these views - add a back or back-three-quarter view; the top view suggests the bump and silver lens rims are present but the lilac tint of the plateau is unconfirmed. Side buttons are only faintly visible on the side view; ensure the elongated pill buttons protrude slightly from the right rail and a power button on the left rail per spec. Corner radius looks slightly tight in front view - soften toward the reference's larger radius.",
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
    name: "iPhone 17",
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
