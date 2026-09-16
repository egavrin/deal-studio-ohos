/**
 * The named icons, as path data.
 *
 * Drawn rather than shipped. The renderer already turns an SVG path into an
 * ArkUI Path for ui.Path, so an icon is a path under a name -- no image assets,
 * no font, nothing to go missing on a device, and the same 0..100 box every
 * drawing in this system uses.
 *
 * They are *stroked*, not filled. A filled silhouette needs a counter-wound
 * subpath wherever the shape has a hole -- the ring of a magnifier, the bowl of
 * a clock -- and those are both awkward to write and easy to get subtly wrong.
 * A stroked outline has no holes to cut, reads better at sixteen points, and is
 * what every icon set now in use looks like. Stroke width is 8 in the 0..100
 * box, which lands near 1.6 at the size an icon is actually drawn.
 *
 * Pure data, like VeraUiCatalog and VeraTheme: no imports, so the catalogue can
 * name these without dragging the renderer in behind it.
 */

/**
 * The stroke, in the same units the paths are drawn in.
 *
 * A string with the unit rather than a bare number, because those units are
 * pixels: ArkUI reads a Path's commands as px, so the Shape's viewPort and the
 * stroke have to say px too or the three disagree and the glyph comes out at a
 * third of its size. Measured on device -- a bare number here put the ink at
 * 0.25 of its box instead of 0.78.
 */
export const ICON_STROKE: string = '8px'

/** The box the paths are drawn in, as the viewPort has to state it. */
export const ICON_VIEWPORT: string = '100px'
export const ICON_ORIGIN: string = '0px' 

/**
 * Name to path. The names are the vocabulary a generated program may use, so
 * they are ordinary words for what the thing is, not what it looks like.
 */
export const ICONS: Map<string, string> = new Map<string, string>([
  ['check', 'M 15 52.33 L 38.33 75.67 L 85 24.33'],
  ['close', 'M 15 15 L 85 85 M 85 15 L 15 85'],
  ['plus', 'M 50 15 L 50 85 M 15 50 L 85 50'],
  ['minus', 'M 15 50 L 85 50'],
  ['chevron-right', 'M 32.5 15 L 67.5 50 L 32.5 85'],
  ['navigate', 'M 84 15 L 16 43 L 46 55 L 58 85 Z'],
  ['pin', 'M 50 85 C 50 85 76 59 76 41 A 26 26 0 0 0 24 41 C 24 59 50 85 50 85 Z M 62 41 A 12 12 0 0 1 38 41 A 12 12 0 0 1 62 41'],
  ['calendar', 'M 17.33 26.67 H 82.67 V 85 H 17.33 Z M 17.33 45.33 H 82.67 M 33.67 15 V 33.67 M 66.33 15 V 33.67'],
  ['clock', 'M 15 50 A 35 35 0 1 1 85 50 A 35 35 0 1 1 15 50 M 50 25.94 V 52.19 L 67.5 63.12'],
  ['star', 'M 50 15.97 L 60.69 38.33 L 85 42.22 L 67.5 59.72 L 71.39 84.03 L 50 72.36 L 28.61 84.03 L 32.5 59.72 L 15 42.22 L 39.31 38.33 Z'],
  ['user', 'M 50 47 A 16 16 0 1 1 50 15 A 16 16 0 1 1 50 47 M 20 85 C 20 67 34 57 50 57 C 66 57 80 67 80 85'],
  ['warning', 'M 50 18.89 L 85 81.11 H 15 Z M 50 44.17 V 61.67 M 50 71.39 V 73.33'],
  ['info', 'M 15 50 A 35 35 0 1 1 85 50 A 35 35 0 1 1 15 50 M 50 45.62 V 69.69 M 50 30.31 V 32.5'],
  ['trash', 'M 17.33 26.67 H 82.67 M 38.33 26.67 V 15 H 61.67 V 26.67 M 26.67 26.67 V 85 H 73.33 V 26.67 M 41.83 43 V 68.67 M 58.17 43 V 68.67'],
  ['list', 'M 33.06 25.16 H 85 M 33.06 50 H 85 M 33.06 74.84 H 85 M 15 25.16 H 17.26 M 15 50 H 17.26 M 15 74.84 H 17.26'],
  ['chart', 'M 15 81.5 V 48.83 M 38.33 81.5 V 18.5 M 61.67 81.5 V 58.17 M 85 81.5 V 32.5'],
])

/** The names a program may use, for the prompt and for the compiler's check. */
export function iconNames(): string[] {
  let names: string[] = []
  ICONS.forEach((_path: string, name: string) => { names.push(name) })
  return names
}

/** The path for a name; empty when there is no such icon. */
export function iconPath(name: string): string {
  let p = ICONS.get(name)
  return p !== undefined ? p : ''
}
