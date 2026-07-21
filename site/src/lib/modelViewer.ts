import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
import { MeshoptDecoder } from "three/examples/jsm/libs/meshopt_decoder.module.js";

// One meshopt-enabled loader shared across every viewer instance.
let sharedLoader: GLTFLoader | null = null;
function loader(): GLTFLoader {
  if (!sharedLoader) {
    sharedLoader = new GLTFLoader();
    sharedLoader.setMeshoptDecoder(MeshoptDecoder);
  }
  return sharedLoader;
}

export interface ViewerOptions {
  autoRotate?: boolean;
  autoRotateSpeed?: number;
  reducedMotion?: boolean;
  // fraction of the framing distance the camera sits at (1 = default frame)
  distance?: number;
  onLoad?: () => void;
}

interface MatState {
  mat: THREE.Material;
  transparent: boolean;
  opacity: number;
  depthWrite: boolean;
}

const IDLE_MS = 1000 / 30 - 0.5;

export class ModelViewer {
  private container: HTMLElement;
  private renderer: THREE.WebGLRenderer;
  private scene: THREE.Scene;
  private camera: THREE.PerspectiveCamera;
  private controls: OrbitControls;
  private pmrem: THREE.PMREMGenerator;
  private envRT: THREE.WebGLRenderTarget;

  private current: THREE.Group | null = null;
  private fading: { group: THREE.Group; states: MatState[]; dir: 1 | -1 }[] = [];
  private fadeStart = 0;
  private fadeDur = 380;
  private fadeActive = false;

  private baseRadius = 3;
  private distanceFactor: number;
  private target = new THREE.Vector3(0, 0, 0);

  private raf = 0;
  private lastFrame = -Infinity;
  private onScreen = false;
  private interacting = false;
  private needsRender = true;
  private autoRotateEnabled: boolean;
  private reducedMotion: boolean;
  private resumeTimer = 0;

  private io: IntersectionObserver;
  private ro: ResizeObserver;
  private onVisibility: () => void;
  private disposed = false;
  private onLoadCb?: () => void;

  constructor(container: HTMLElement, opts: ViewerOptions = {}) {
    this.container = container;
    this.autoRotateEnabled = opts.autoRotate ?? true;
    this.reducedMotion = opts.reducedMotion ?? false;
    this.distanceFactor = opts.distance ?? 1;
    this.onLoadCb = opts.onLoad;

    const w = container.clientWidth || 1;
    const h = container.clientHeight || 1;

    this.renderer = new THREE.WebGLRenderer({
      antialias: true,
      alpha: true,
      powerPreference: "high-performance",
    });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.renderer.setSize(w, h, false);
    this.renderer.setClearColor(0x000000, 0); // transparent: CSS page shows through
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.05;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    container.appendChild(this.renderer.domElement);
    this.renderer.domElement.style.width = "100%";
    this.renderer.domElement.style.height = "100%";
    this.renderer.domElement.style.display = "block";
    this.renderer.domElement.style.touchAction = "pan-y";

    this.scene = new THREE.Scene();

    // Neutral studio IBL so sculpts look premium in both themes.
    this.pmrem = new THREE.PMREMGenerator(this.renderer);
    this.envRT = this.pmrem.fromScene(new RoomEnvironment(), 0.04);
    this.scene.environment = this.envRT.texture;

    // A soft key light for a defining highlight on top of the IBL.
    const key = new THREE.DirectionalLight(0xffffff, 1.1);
    key.position.set(2.5, 4, 3);
    this.scene.add(key);
    const fill = new THREE.DirectionalLight(0xffffff, 0.35);
    fill.position.set(-3, 1, -2);
    this.scene.add(fill);

    this.camera = new THREE.PerspectiveCamera(38, w / h, 0.05, 100);
    this.camera.position.set(2.4, 1.4, 3.2);

    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.08;
    this.controls.enablePan = false;
    this.controls.minDistance = 1.2;
    this.controls.maxDistance = 9;
    this.controls.rotateSpeed = 0.9;
    this.controls.autoRotateSpeed = opts.autoRotateSpeed ?? 0.7;
    this.controls.target.copy(this.target);

    this.controls.addEventListener("change", () => {
      this.needsRender = true;
    });
    this.controls.addEventListener("start", () => {
      this.interacting = true;
      this.controls.autoRotate = false;
      if (this.resumeTimer) window.clearTimeout(this.resumeTimer);
    });
    this.controls.addEventListener("end", () => {
      this.interacting = false;
      if (this.autoRotateEnabled && !this.reducedMotion) {
        this.resumeTimer = window.setTimeout(() => {
          this.controls.autoRotate = true;
          this.needsRender = true;
        }, 2600);
      }
    });

    // Visibility gating: only the on-screen viewer runs its loop.
    this.io = new IntersectionObserver(
      (entries) => {
        const vis = entries[0]?.isIntersecting ?? false;
        if (vis && !this.onScreen) {
          this.onScreen = true;
          this.needsRender = true;
          if (this.autoRotateEnabled && !this.reducedMotion && !this.interacting) {
            this.controls.autoRotate = true;
          }
          this.start();
        } else if (!vis && this.onScreen) {
          this.onScreen = false;
          this.stop();
        }
      },
      { threshold: 0.12 },
    );
    this.io.observe(container);

    this.ro = new ResizeObserver(() => this.resize());
    this.ro.observe(container);

    this.onVisibility = () => {
      if (document.hidden) this.stop();
      else if (this.onScreen) this.start();
    };
    document.addEventListener("visibilitychange", this.onVisibility);
  }

  private resize() {
    if (this.disposed) return;
    const w = this.container.clientWidth || 1;
    const h = this.container.clientHeight || 1;
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.needsRender = true;
  }

  private start() {
    if (this.disposed || this.raf) return;
    this.raf = requestAnimationFrame(this.tick);
  }

  private stop() {
    if (this.raf) cancelAnimationFrame(this.raf);
    this.raf = 0;
  }

  private tick = (t: number) => {
    this.raf = requestAnimationFrame(this.tick);
    const rotating = this.controls.autoRotate && !this.interacting;
    const busy = this.interacting || this.fadeActive || this.needsRender;
    if (!rotating && !busy) return;
    // Cap idle auto-rotate to ~30fps; full rate while interacting or fading.
    if (rotating && !busy) {
      if (t - this.lastFrame < IDLE_MS) return;
    }
    this.lastFrame = t;
    this.needsRender = false;
    if (this.fadeActive) this.stepFade(t);
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  };

  private frameModel(group: THREE.Group) {
    const box = new THREE.Box3().setFromObject(group);
    const size = new THREE.Vector3();
    const center = new THREE.Vector3();
    box.getSize(size);
    box.getCenter(center);
    // Recenter the model at the origin.
    group.position.sub(center);
    const maxDim = Math.max(size.x, size.y, size.z) || 1;
    const fov = (this.camera.fov * Math.PI) / 180;
    this.baseRadius = (maxDim / 2 / Math.tan(fov / 2)) * 1.5;
    this.applyView();
  }

  private spherical = new THREE.Spherical();
  private az = Math.PI * 0.16; // azimuth
  private pol = Math.PI * 0.42; // polar (from +Y)
  private applyView() {
    const r = this.baseRadius * this.distanceFactor;
    this.spherical.set(r, this.pol, this.az);
    const p = new THREE.Vector3().setFromSpherical(this.spherical).add(this.target);
    this.camera.position.copy(p);
    this.controls.target.copy(this.target);
    this.camera.lookAt(this.target);
    this.controls.update();
    this.needsRender = true;
  }

  /** Scroll choreography hook: azimuth/polar in degrees, distance factor. */
  setView(v: { azimuth?: number; polar?: number; distance?: number }) {
    if (v.azimuth != null) this.az = (v.azimuth * Math.PI) / 180;
    if (v.polar != null) this.pol = (v.polar * Math.PI) / 180;
    if (v.distance != null) this.distanceFactor = v.distance;
    this.controls.autoRotate = false;
    this.applyView();
  }

  setAutoRotate(on: boolean) {
    this.autoRotateEnabled = on && !this.reducedMotion;
    if (!this.autoRotateEnabled) {
      this.controls.autoRotate = false;
    } else if (this.onScreen && !this.interacting) {
      this.controls.autoRotate = true;
      this.needsRender = true;
    }
  }

  private collectMats(group: THREE.Group): MatState[] {
    const out: MatState[] = [];
    const seen = new Set<THREE.Material>();
    group.traverse((o) => {
      const mesh = o as THREE.Mesh;
      if (!mesh.isMesh) return;
      const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
      for (const m of mats) {
        if (!m || seen.has(m)) continue;
        seen.add(m);
        out.push({
          mat: m,
          transparent: m.transparent,
          opacity: m.opacity,
          depthWrite: m.depthWrite,
        });
      }
    });
    return out;
  }

  private setGroupOpacity(states: MatState[], factor: number, fading: boolean) {
    for (const s of states) {
      if (fading) {
        s.mat.transparent = true;
        s.mat.depthWrite = false;
        s.mat.opacity = s.opacity * factor;
      } else {
        s.mat.transparent = s.transparent;
        s.mat.depthWrite = s.depthWrite;
        s.mat.opacity = s.opacity;
      }
      s.mat.needsUpdate = true;
    }
  }

  private stepFade(t: number) {
    const k = Math.min(1, (t - this.fadeStart) / this.fadeDur);
    const eased = k * k * (3 - 2 * k);
    for (const f of this.fading) {
      const factor = f.dir === 1 ? eased : 1 - eased;
      this.setGroupOpacity(f.states, factor, true);
    }
    if (k >= 1) {
      // Finish: restore incoming materials, drop the outgoing group.
      for (const f of this.fading) {
        if (f.dir === 1) {
          this.setGroupOpacity(f.states, 1, false);
        } else {
          this.scene.remove(f.group);
          this.disposeGroup(f.group);
        }
      }
      this.fading = [];
      this.fadeActive = false;
    }
  }

  async load(url: string): Promise<void> {
    const gltf = await loader().loadAsync(url);
    if (this.disposed) return;
    const group = gltf.scene;
    this.scene.add(group);
    this.current = group;
    this.frameModel(group);
    this.onLoadCb?.();
    this.needsRender = true;
    if (this.onScreen) this.start();
  }

  /** Crossfade from the current model to a new one (timeline scrubbing). */
  async setModel(url: string): Promise<void> {
    const gltf = await loader().loadAsync(url);
    if (this.disposed) return;
    const incoming = gltf.scene;
    this.scene.add(incoming);
    // Match the framing transform of the current model's fit.
    this.frameModel(incoming);

    if (this.current) {
      const outStates = this.collectMats(this.current);
      const inStates = this.collectMats(incoming);
      this.setGroupOpacity(inStates, 0, true);
      this.fading = [
        { group: this.current, states: outStates, dir: -1 },
        { group: incoming, states: inStates, dir: 1 },
      ];
      this.fadeStart = performance.now();
      this.fadeActive = true;
    }
    this.current = incoming;
    this.needsRender = true;
    if (this.onScreen) this.start();
  }

  private disposeGroup(group: THREE.Object3D) {
    group.traverse((o) => {
      const mesh = o as THREE.Mesh;
      if (mesh.isMesh) {
        mesh.geometry?.dispose();
        const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
        for (const m of mats) {
          if (!m) continue;
          for (const key of Object.keys(m) as (keyof THREE.Material)[]) {
            const val = (m as unknown as Record<string, unknown>)[key as string];
            if (val && (val as THREE.Texture).isTexture) (val as THREE.Texture).dispose();
          }
          m.dispose();
        }
      }
    });
  }

  dispose() {
    this.disposed = true;
    this.stop();
    if (this.resumeTimer) window.clearTimeout(this.resumeTimer);
    this.io.disconnect();
    this.ro.disconnect();
    document.removeEventListener("visibilitychange", this.onVisibility);
    this.controls.dispose();
    if (this.current) this.disposeGroup(this.current);
    for (const f of this.fading) this.disposeGroup(f.group);
    this.envRT.dispose();
    this.pmrem.dispose();
    this.scene.environment = null;
    this.renderer.dispose();
    this.renderer.forceContextLoss();
    const gl = this.renderer.getContext();
    (gl.getExtension("WEBGL_lose_context") as WEBGL_lose_context | null)?.loseContext();
    if (this.renderer.domElement.parentNode === this.container) {
      this.container.removeChild(this.renderer.domElement);
    }
  }
}
