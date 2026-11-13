/**
 * How a ui.World looks: the look "B" recipe in one place, as plain numbers.
 *
 * Soft GPU light with shadows and colours that stay close to the theme: metallic-roughness materials whose base colour is
 * the theme colour turned from sRGB into linear, one sun of intensity 14 standing at (3, 10, 4) and looking at the origin
 * with shadows on, an environment that adds 0.55 of indirect light and draws no background of its own, and no post
 * processing (an empty PostProcessSettings: null still tone-maps). These numbers were picked on the phone in the
 * ArkGraphics3D spike; light only (no dark-theme tuning).
 *
 * Also the geometry the renderer and, later, the physics share: a table's top and walls, a die's pips, the default camera
 * when a program gives none, rotations as quaternions and the orbit of a dragged camera. components/VeraWorld3D.ets turns
 * all of it into ArkGraphics3D nodes and is the only file that imports that kit.
 *
 * Pure: imports only relative modules, never a platform kit, so tools/vera-harness loads it under node.
 */

import { ResolvedTheme } from './VeraTheme'
import { gfxColor } from './GfxPaint'
import { WorldSpec, BodySpec, CameraSpec, TableSpec } from './VeraScene'

/** The sun: a directional light this bright (the kit's default of 1 does practically nothing), from here, at the origin. */
export const LOOK_SUN_INTENSITY: number = 14
export const LOOK_SUN_POSITION: number[] = [3, 10, 4]
export const LOOK_SUN_TARGET: number[] = [0, 0, 0]
export const LOOK_SHADOWS: boolean = true
/** Indirect diffuse and specular light from the environment, each channel. */
export const LOOK_AMBIENT: number = 0.55
/** Vertical field of view of the camera, in radians (the kit's own default, set explicitly). */
export const LOOK_FOV: number = Math.PI / 3

/** Theme roles for what the program does not colour itself, or colours with "". */
export const LOOK_FLOOR_ROLE: string = 'surface'
export const LOOK_TABLE_ROLE: string = 'surface'
export const LOOK_PIP_ROLE: string = 'ink'
export const LOOK_BACKGROUND_ROLE: string = 'background'

/**
 * Ground colours, as the phone showed they need to be. A floor in a light neutral role ("surface", "background", "white"
 * or none) is drawn as the page background a little darker, so the horizon melts into the page instead of standing out
 * as a white band; a table in one is felt, so white dice show on it. Any other colour is used as written, except that a
 * table as close in colour to one of its dice as LOOK_TABLE_CLASH is darkened by LOOK_TABLE_DARKEN.
 */
export const LOOK_NEUTRAL_GROUND: string[] = ['', 'surface', 'background', 'white']
export const LOOK_FLOOR_SHADE: number = 0.06
/**
 * The floor is ONE lit METALLIC_ROUGHNESS plane that receives shadows, fully matte (roughness 1, metallic 0, specular 0).
 * The kit's UNLIT_SHADOW_ALPHA layer over an unlit floor drew no shadow on the phone, so the floor itself is lit. Lit, the
 * sun and the ambient light multiply the base colour, so the base is the colour wanted divided by a gain.
 *
 * Calibration (phone, sun 14 from (3,10,4), environment 0.55, no post process): base sRGB #C3C9D2 (linear 0.546, 0.584,
 * 0.644) came out about (240,245,249) mid-floor, linear 0.87, 0.91, 0.95: a gain of about 1.55 (that run also had a
 * specular highlight, which the matte settings remove). With the matte settings the gain is much higher and even across
 * the floor: --ps worldFloorGain 5 gave (218,222,223) and 8 gave (176,180,181) for target #e4e8e8, both a linear gain of
 * about 4.5, and 4.5 gave (229,233,234), within one level of the target (phone, 2026-11-13).
 */
export const FLOOR_LIGHT_GAIN: number = 4.5
/** The gain when a glow body moves the light to the camera (ambient 0.7). UNCALIBRATED: scaled from FLOOR_LIGHT_GAIN. */
export const FLOOR_LIGHT_GAIN_GLOW: number = 4.6
export const FLOOR_ROUGHNESS: number = 1
export const FLOOR_METALLIC: number = 0
export const FLOOR_SPECULAR: number = 0

/** Development only (`--ps worldFloorGain <n>`, set by EntryAbility): replaces the gain when it is above 0. */
let floorGainOverride: number = 0
export function setFloorGainOverride(g: number): void { floorGainOverride = Number.isFinite(g) && g > 0 ? g : 0 }
export function floorGain(glows: boolean): number {
  return floorGainOverride > 0 ? floorGainOverride : (glows ? FLOOR_LIGHT_GAIN_GLOW : FLOOR_LIGHT_GAIN)
}

export const LOOK_FELT: string = '#35654d'
export const LOOK_TABLE_CLASH: number = 0.2
export const LOOK_TABLE_DARKEN: number = 0.4
/**
 * A world with a glowing body (a sun) is lit from the eye: the light stands at the camera and looks where it looks,
 * with more ambient light, so whatever side of a planet the camera is turned to is lit (the kit has no point light).
 */
export const LOOK_GLOW_AMBIENT: number = 0.7

/** A table: its top is a slab this thick whose upper face is y = 0; its walls stand this high above the top and are this thick. */
export const TABLE_TOP_THICKNESS: number = 0.04
export const TABLE_WALL_HEIGHT_RATIO: number = 0.12
export const TABLE_WALL_MIN_HEIGHT: number = 0.03
export const TABLE_WALL_THICKNESS_RATIO: number = 0.025

/** Pips on a die of half-size h: centres at 0.93 h out on the face, radius 0.15 h, offsets of +-0.5 h. */
export const PIP_DEPTH: number = 0.93
export const PIP_RADIUS: number = 0.15
export const PIP_OFFSET: number = 0.5

// ---------------------------------------------------------------- colour

function hexByte(s: string): number { return parseInt(s, 16) }

/**
 * A colour as the program wrote it -- a theme role, #rgb, #rrggbb or #rrggbbaa -- as sRGB [r, g, b, a] in 0..1, through
 * the same resolution std/gfx paints with (gfxColor), so a world in "accent" is the accent of the screen around it.
 */
export function lookRgba(t: ResolvedTheme, color: string, fallbackRole: string = 'ink'): number[] {
  let css = gfxColor(t, color.length > 0 ? color : fallbackRole)
  if (css.length === 7 && css.charAt(0) === '#') {
    return [hexByte(css.substring(1, 3)) / 255, hexByte(css.substring(3, 5)) / 255, hexByte(css.substring(5, 7)) / 255, 1]
  }
  if (css.length === 4 && css.charAt(0) === '#') {
    let d = css.substring(1)
    return [hexByte(d.charAt(0) + d.charAt(0)) / 255, hexByte(d.charAt(1) + d.charAt(1)) / 255, hexByte(d.charAt(2) + d.charAt(2)) / 255, 1]
  }
  if (css.startsWith('rgba(') && css.endsWith(')')) {
    let parts = css.substring(5, css.length - 1).split(',')
    if (parts.length === 4) {
      return [Number(parts[0]) / 255, Number(parts[1]) / 255, Number(parts[2]) / 255, Number(parts[3])]
    }
  }
  return [0, 0, 0, 1]
}

/** One sRGB channel (0..1) in linear light, the space the renderer lights in. */
export function srgbToLinear(c: number): number {
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
}

/** lookRgba in linear light: what a material's base colour factor is set to. Alpha stays as it is. */
export function lookLinear(t: ResolvedTheme, color: string, fallbackRole: string = 'ink'): number[] {
  let c = lookRgba(t, color, fallbackRole)
  return [srgbToLinear(c[0]), srgbToLinear(c[1]), srgbToLinear(c[2]), c[3]]
}

/** What two colours share a material by: the colour they come out as, and whether it glows. */
export function lookColorKey(t: ResolvedTheme, color: string, glow: boolean, fallbackRole: string = 'ink'): string {
  return (glow ? 'glow:' : 'lit:') + gfxColor(t, color.length > 0 ? color : fallbackRole).toLowerCase()
}

function hexOf(c: number[]): string {
  let out = '#'
  for (let k = 0; k < 3; k++) {
    let v = Math.max(0, Math.min(255, Math.round(c[k] * 255)))
    out += (v < 16 ? '0' : '') + v.toString(16)
  }
  return out
}

function darker(c: number[], by: number): number[] {
  return [c[0] * (1 - by), c[1] * (1 - by), c[2] * (1 - by), c[3]]
}

/** The colour a floor is drawn in (see LOOK_NEUTRAL_GROUND): a colour as the program writes one. */
export function floorColor(t: ResolvedTheme, color: string): string {
  if (LOOK_NEUTRAL_GROUND.indexOf(color) < 0) { return color }
  return hexOf(darker(lookRgba(t, LOOK_BACKGROUND_ROLE), LOOK_FLOOR_SHADE))
}

/** The floor's base colour, linear: the colour wanted divided by the gain, clamped to [0, 1]. */
export function floorBaseLinear(t: ResolvedTheme, color: string, gain: number): number[] {
  let target = lookLinear(t, floorColor(t, color), LOOK_FLOOR_ROLE)
  let out: number[] = []
  for (let k = 0; k < 3; k++) { out.push(Math.min(1, Math.max(0, target[k] / gain))) }
  out.push(1)
  return out
}

/** A linear colour as #rrggbb (for the log). */
export function linearHex(c: number[]): string {
  let out: number[] = []
  for (let k = 0; k < 3; k++) {
    let lin = c[k]
    out.push(lin <= 0.0031308 ? lin * 12.92 : 1.055 * Math.pow(lin, 1 / 2.4) - 0.055)
  }
  out.push(1)
  return hexOf(out)
}

/** The colour a table is drawn in, given the colours of the dice on it (see LOOK_NEUTRAL_GROUND). */
export function tableColor(t: ResolvedTheme, color: string, dieColors: string[]): string {
  let base = LOOK_NEUTRAL_GROUND.indexOf(color) >= 0 ? LOOK_FELT : color
  let c = lookRgba(t, base)
  for (let die of dieColors) {
    let d = lookRgba(t, die)
    if (Math.hypot(c[0] - d[0], c[1] - d[1], c[2] - d[2]) < LOOK_TABLE_CLASH) { return hexOf(darker(c, LOOK_TABLE_DARKEN)) }
  }
  return base
}

/** Whether something in the world glows: then the light follows the eye (LOOK_GLOW_AMBIENT). */
export function worldGlows(spec: WorldSpec): boolean {
  for (let b of spec.bodies) { if (b.glow) { return true } }
  return false
}

// ---------------------------------------------------------------- rotations

/** Degrees about x, then y, then z (as VeraMotion.poseMatrix) as a quaternion [x, y, z, w]: q = qz * qy * qx. */
export function quatXYZ(degX: number, degY: number, degZ: number): number[] {
  let hx = degX * Math.PI / 360
  let hy = degY * Math.PI / 360
  let hz = degZ * Math.PI / 360
  let cx = Math.cos(hx)
  let sx = Math.sin(hx)
  let cy = Math.cos(hy)
  let sy = Math.sin(hy)
  let cz = Math.cos(hz)
  let sz = Math.sin(hz)
  // qy * qx
  let w1 = cy * cx
  let x1 = cy * sx
  let y1 = sy * cx
  let z1 = -sy * sx
  // qz * (qy * qx)
  return [cz * x1 - sz * y1, cz * y1 + sz * x1, cz * z1 + sz * w1, cz * w1 - sz * z1]
}

function sub3(a: number[], b: number[]): number[] { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]] }
function dot3(a: number[], b: number[]): number { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
function cross3(a: number[], b: number[]): number[] {
  return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}
function norm3(a: number[]): number[] {
  let d = Math.sqrt(dot3(a, a))
  return d > 0 ? [a[0] / d, a[1] / d, a[2] / d] : [0, 0, 0]
}

/**
 * The rotation [x, y, z, w] that makes a node at eye look at centre with up roughly up: the camera and the sun. From the
 * ArkGraphics3D docs sample, as the spike used it; a view straight down (or up) takes +z as its up instead.
 */
/**
 * Where the sun stands for a camera: LOOK_SUN_SIDE_DEG to the right of the way the camera looks (seen from above), at
 * LOOK_SUN_ELEVATION_DEG, LOOK_SUN_DISTANCE from the look point. A sun fixed in the world stood behind a camera placed on
 * the same side as it (world-cubes: camera at (1.6, 1, 2.2), sun at (3, 10, 4)), so every shadow fell behind its body and
 * none could be seen; from the side, shadows fall across the view. The elevation is the old fixed sun's, so the floor's
 * calibrated light gain (FLOOR_LIGHT_GAIN) still holds -- a level floor's light depends only on the sun's height.
 */
export const LOOK_SUN_SIDE_DEG: number = 75
export const LOOK_SUN_ELEVATION_DEG: number = 63.43
export const LOOK_SUN_DISTANCE: number = 11.2

export function sunFor(eye: number[], look: number[]): number[] {
  let az = Math.atan2(eye[0] - look[0], eye[2] - look[2]) + LOOK_SUN_SIDE_DEG * Math.PI / 180
  let el = LOOK_SUN_ELEVATION_DEG * Math.PI / 180
  let flat = LOOK_SUN_DISTANCE * Math.cos(el)
  return [look[0] + flat * Math.sin(az), look[1] + LOOK_SUN_DISTANCE * Math.sin(el), look[2] + flat * Math.cos(az)]
}

export function lookAtQuat(eye: number[], centre: number[], up: number[]): number[] {
  let f = norm3(sub3(centre, eye))
  let side = cross3(f, up)
  if (dot3(side, side) < 1e-12) { side = cross3(f, [0, 0, 1]) }
  let m0 = norm3(side)
  let m1 = cross3(m0, f)
  let m2 = [-f[0], -f[1], -f[2]]
  let t = 0
  let q: number[]
  if (m2[2] < 0) {
    if (m0[0] > m1[1]) {
      t = 1.0 + m0[0] - m1[1] - m2[2]
      q = [t, m0[1] + m1[0], m2[0] + m0[2], m1[2] - m2[1]]
    } else {
      t = 1.0 - m0[0] + m1[1] - m2[2]
      q = [m0[1] + m1[0], t, m1[2] + m2[1], m2[0] - m0[2]]
    }
  } else {
    if (m0[0] < -m1[1]) {
      t = 1.0 - m0[0] - m1[1] + m2[2]
      q = [m2[0] + m0[2], m1[2] + m2[1], t, m0[1] - m1[0]]
    } else {
      t = 1.0 + m0[0] + m1[1] + m2[2]
      q = [m1[2] - m2[1], m2[0] - m0[2], m0[1] - m1[0], t]
    }
  }
  let s = 0.5 / Math.sqrt(t)
  return [q[0] * s, q[1] * s, q[2] * s, q[3] * s]
}

// ---------------------------------------------------------------- the camera

export class CameraPose {
  eye: number[] = [0, 3, 6]
  look: number[] = [0, 0, 0]
  near: number = 0.05
  far: number = 100
  fov: number = LOOK_FOV
  /** Whether a drag on the world circles the eye round the look point. */
  orbit: boolean = false
}

/** A sphere [cx, cy, cz, r] round everything in the world wherever its orbits take it, the table included; null for an empty world. */
export function worldBounds(spec: WorldSpec): number[] | null {
  let byId = new Map<string, BodySpec>()
  for (let b of spec.bodies) { byId.set(b.id, b) }
  let spheres: number[][] = []
  for (let b of spec.bodies) {
    let half = Math.sqrt(b.dims[0] * b.dims[0] + b.dims[1] * b.dims[1] + b.dims[2] * b.dims[2]) / 2
    // An orbiting body may be anywhere on a ring round its centre, which may itself be anywhere on one: the chain's root
    // and the sum of the radii bound it.
    let at: BodySpec = b
    let reach = 0
    let steps = 0
    while (steps < spec.bodies.length) {
      let o = at.orbit
      if (o === null) { break }
      reach += Math.abs(o.radius)
      let centre = byId.get(o.centre)
      if (centre === undefined) { break }
      at = centre
      steps++
    }
    spheres.push([at.position[0], at.position[1], at.position[2], half + reach])
  }
  if (spec.table !== null) {
    for (let part of tableParts(spec.table as TableSpec)) {
      spheres.push([part[0], part[1], part[2], Math.sqrt(part[3] * part[3] + part[4] * part[4] + part[5] * part[5]) / 2])
    }
  }
  if (spheres.length === 0) { return null }
  let lo = [Infinity, Infinity, Infinity]
  let hi = [-Infinity, -Infinity, -Infinity]
  for (let s of spheres) {
    for (let k = 0; k < 3; k++) {
      lo[k] = Math.min(lo[k], s[k] - s[3])
      hi[k] = Math.max(hi[k], s[k] + s[3])
    }
  }
  let c = [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2]
  let r = 0
  for (let s of spheres) {
    let d = sub3([s[0], s[1], s[2]], c)
    r = Math.max(r, Math.sqrt(dot3(d, d)) + s[3])
  }
  return [c[0], c[1], c[2], Math.max(r, 0.01)]
}

/** Near and far planes for an eye this far from what it looks at, with the world this big. */
function planes(pose: CameraPose, distance: number, radius: number): void {
  pose.near = Math.max(0.01, Math.min(distance * 0.05, Math.max(distance - radius, 0.01) * 0.5))
  pose.far = Math.max(50, (distance + radius) * 4)
}

/**
 * Where the camera stands when the program gives none: in front of the world and above it, looking at the middle, far
 * enough back that the whole bounding sphere fits the narrower of the two fields of view (aspect = width / height).
 */
export function defaultCamera(spec: WorldSpec, aspect: number): CameraPose {
  let pose = new CameraPose()
  let bounds = worldBounds(spec)
  if (bounds === null) {
    planes(pose, 6.7, 1)
    return pose
  }
  let half = LOOK_FOV / 2
  let a = aspect > 0 ? aspect : 1
  if (a < 1) { half = Math.atan(Math.tan(half) * a) }
  let distance = bounds[3] / Math.sin(half) * 1.08
  let dir = norm3([0, 0.6, 1])
  pose.look = [bounds[0], bounds[1], bounds[2]]
  pose.eye = [bounds[0] + dir[0] * distance, bounds[1] + dir[1] * distance, bounds[2] + dir[2] * distance]
  planes(pose, distance, bounds[3])
  return pose
}

/** The camera the world is seen through: the program's, or the default one. */
export function worldCamera(spec: WorldSpec, aspect: number): CameraPose {
  if (spec.camera === null) { return defaultCamera(spec, aspect) }
  let c = spec.camera as CameraSpec
  let pose = new CameraPose()
  pose.eye = [c.x, c.y, c.z]
  pose.look = [c.lookX, c.lookY, c.lookZ]
  pose.orbit = c.orbit
  let d = sub3(pose.eye, pose.look)
  let bounds = worldBounds(spec)
  planes(pose, Math.sqrt(dot3(d, d)), bounds !== null ? bounds[3] : 1)
  return pose
}

/**
 * The eye after a drag: turned yaw radians round the vertical through the look point and tilted pitch radians, at the
 * same distance; the tilt stays between minPitch and maxPitch (above the floor when there is one).
 */
export function orbitEye(eye: number[], look: number[], yaw: number, pitch: number, minPitch: number, maxPitch: number): number[] {
  let d = sub3(eye, look)
  let r = Math.sqrt(dot3(d, d))
  if (r <= 0) { return [eye[0], eye[1], eye[2]] }
  let theta = Math.atan2(d[0], d[2]) + yaw
  let phi = Math.asin(Math.max(-1, Math.min(1, d[1] / r))) + pitch
  phi = Math.max(minPitch, Math.min(maxPitch, phi))
  let flat = r * Math.cos(phi)
  return [look[0] + flat * Math.sin(theta), look[1] + r * Math.sin(phi), look[2] + flat * Math.cos(theta)]
}

/** The camera's forward, right and up, unit vectors: the same frame lookAtQuat turns the camera to. */
export function cameraBasis(pose: CameraPose): number[][] {
  let f = norm3(sub3(pose.look, pose.eye))
  let side = cross3(f, [0, 1, 0])
  if (dot3(side, side) < 1e-12) { side = cross3(f, [0, 0, 1]) }
  let r = norm3(side)
  return [f, r, cross3(r, f)]
}

/**
 * Where a point lands in a box width by height (vp) seen through the camera, [x, y, depth] with x, y from the box's top
 * left; null behind the eye. The field of view is vertical, as defaultCamera takes it.
 */
export function projectPoint(pose: CameraPose, width: number, height: number, p: number[]): number[] | null {
  if (width <= 0 || height <= 0) { return null }
  let basis = cameraBasis(pose)
  let d = sub3(p, pose.eye)
  let depth = dot3(d, basis[0])
  if (depth <= 1e-6) { return null }
  let tanHalf = Math.tan(pose.fov / 2)
  let ny = dot3(d, basis[2]) / (depth * tanHalf)
  let nx = dot3(d, basis[1]) / (depth * tanHalf * (width / height))
  return [(nx + 1) / 2 * width, (1 - ny) / 2 * height, depth]
}

/** Metres one vp covers at this depth in a box this tall. */
export function metresPerVp(pose: CameraPose, height: number, depth: number): number {
  return height > 0 ? 2 * depth * Math.tan(pose.fov / 2) / height : 0
}

/**
 * A drag of dx right and dy down on the screen as a direction along the floor: the camera's right for right, its
 * forward flattened onto the floor for up. A unit [x, 0, z]; [0, 0, 0] for no drag.
 */
export function floorDirection(pose: CameraPose, dx: number, dy: number): number[] {
  let basis = cameraBasis(pose)
  let ahead = [basis[0][0], 0, basis[0][2]]
  if (dot3(ahead, ahead) < 1e-12) { ahead = [basis[2][0], 0, basis[2][2]] }
  ahead = norm3(ahead)
  let right = norm3([basis[1][0], 0, basis[1][2]])
  return norm3([right[0] * dx - ahead[0] * dy, 0, right[2] * dx - ahead[2] * dy])
}

// ---------------------------------------------------------------- the table, the floor, a die

/** A table as boxes [cx, cy, cz, w, h, d]: the top (its upper face at y = 0), then the walls round it, -z, +z, -x, +x. */
export function tableParts(table: TableSpec): number[][] {
  let w = table.width
  let d = table.depth
  let wallH = Math.max(TABLE_WALL_MIN_HEIGHT, Math.min(w, d) * TABLE_WALL_HEIGHT_RATIO)
  let wallT = Math.max(0.01, Math.min(w, d) * TABLE_WALL_THICKNESS_RATIO)
  let y = wallH / 2
  return [
    [0, -TABLE_TOP_THICKNESS / 2, 0, w + 2 * wallT, TABLE_TOP_THICKNESS, d + 2 * wallT],
    [0, y, -(d + wallT) / 2, w + 2 * wallT, wallH, wallT],
    [0, y, (d + wallT) / 2, w + 2 * wallT, wallH, wallT],
    [-(w + wallT) / 2, y, 0, wallT, wallH, d],
    [(w + wallT) / 2, y, 0, wallT, wallH, d],
  ]
}

/** How wide the floor plane is drawn: far past everything in the world, so its edge stays out of sight. */
export function floorSize(spec: WorldSpec): number {
  let bounds = worldBounds(spec)
  let reach = bounds !== null ? Math.sqrt(bounds[0] * bounds[0] + bounds[2] * bounds[2]) + bounds[3] : 1
  return Math.max(40, reach * 12)
}

/**
 * A die's pips, for a die of half-size h, as [face, x, y, z] in the die's own coordinates, radius PIP_RADIUS * h each.
 * Faces: +z 1, -z 6, +x 3, -x 4, +y 2, -y 5 -- the convention topFace reads, checked on the phone.
 */
export function pipLayout(h: number): number[][] {
  let layouts: number[][] = [[0, 0], [-1, -1, 1, 1], [-1, -1, 0, 0, 1, 1], [-1, -1, -1, 1, 1, -1, 1, 1],
    [-1, -1, -1, 1, 0, 0, 1, -1, 1, 1], [-1, -1, -1, 0, -1, 1, 1, -1, 1, 0, 1, 1]]
  // [face, normal axis, sign]
  let faces: number[][] = [[1, 2, 1], [6, 2, -1], [3, 0, 1], [4, 0, -1], [2, 1, 1], [5, 1, -1]]
  let pips: number[][] = []
  for (let f of faces) {
    let lay = layouts[f[0] - 1]
    for (let k = 0; k < lay.length; k += 2) {
      let p = [0, 0, 0]
      p[f[1]] = f[2] * h * PIP_DEPTH
      p[(f[1] + 1) % 3] = lay[k] * h * PIP_OFFSET
      p[(f[1] + 2) % 3] = lay[k + 1] * h * PIP_OFFSET
      pips.push([f[0], p[0], p[1], p[2]])
    }
  }
  return pips
}
