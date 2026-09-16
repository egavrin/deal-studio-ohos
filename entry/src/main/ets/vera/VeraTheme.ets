/**
 * The one description of how a style name becomes a colour, a size or a gap.
 *
 * Until now every one of those was a hex literal inside a ternary in
 * VeraPreview.renderNode -- '#F3F6FA' appeared in four branches, '#007DFF' in
 * three, and the type scale existed only as the numbers 24/18/15/12/32 written
 * out wherever a Text was drawn. Two generated apps could not look different
 * from one another, because there was nothing to vary.
 *
 * A program now names a *preset* and that one word settles the whole screen:
 * palette, radii, rhythm and type together. That is deliberate. The axes are
 * not offered separately, because a model picking eight knobs independently
 * picks eight knobs that disagree; picking one character does not.
 *
 * Like VeraUiCatalog this module is pure data. It imports nothing -- not the
 * compiler, not ArkUI -- so weights are plain numbers (400/500/700, which
 * .fontWeight() accepts) rather than the FontWeight enum, and the renderer is
 * the only place that knows about ArkUI at all.
 */

/** The six presets, in the order the prompt lists them. */
export const PRESET_NAMES: string[] = [
  'clean', 'soft', 'expressive', 'editorial', 'technical', 'playful']

/**
 * Every value the renderer can ask for, flat.
 *
 * The defaults are the values the renderer used before this module existed, to
 * the digit. That is what makes 'clean' -- and a program with no ui.AppTheme at
 * all, which resolves to 'clean' -- render exactly as it did, so this refactor
 * cannot be a visual regression and the benchmark artifacts are undisturbed.
 */
export class ResolvedTheme {
  preset: string = 'clean'

  // --- palette -------------------------------------------------------------
  primary: string = '#007DFF'
  onPrimary: string = '#FFFFFF'
  /** The primary's container: what an 'accent' surface is filled with. */
  primaryFill: string = '#EBF0FF'
  /**
   * The primary as *text or a rule*, rather than as a filled control.
   *
   * The two cannot be one colour after dark and each stay readable. A filled
   * button wants a primary deep enough that white sits on it; accent text and
   * an accent rail want one light enough to be seen against a near-black
   * surface. By day a single colour does both, which is why success and warning
   * have carried this same pair from the start and primary did not.
   */
  primaryInk: string = '#007DFF'
  secondaryFill: string = '#E0E0E0'
  secondaryInk: string = '#333333'

  /** Behind the whole program. */
  background: string = '#FFFFFF'
  /** A grouped area: card, surface column, image placeholder. */
  surface: string = '#F3F6FA'
  /** A row or cell sitting on top of a surface. */
  surfaceRaised: string = '#FFFFFF'
  surfaceDisabled: string = '#F5F5F5'

  ink: string = '#000000'
  inkStrong: string = '#333333'
  inkSoft: string = '#666666'
  inkMuted: string = '#888888'
  inkDisabled: string = '#CCCCCC'

  line: string = '#D8E1ED'
  lineSoft: string = '#E4EAF2'
  lineStrong: string = '#CBD6E4'

  success: string = '#4CAF50'
  successInk: string = '#2E7D32'
  successFill: string = '#E8F8E8'
  warning: string = '#E65100'
  warningInk: string = '#E65100'
  warningFill: string = '#FFF8E0'
  danger: string = '#F44336'
  dangerInk: string = '#C62828'
  dangerFill: string = '#FFECEC'

  /** Vector shapes, which have their own two names outside the tone set. */
  pathDefault: string = '#37474F'
  pathMuted: string = '#B0BEC5'

  // --- type scale ----------------------------------------------------------
  sizeDisplay: number = 30
  sizeTitle: number = 24
  sizeHeading: number = 18
  sizeBody: number = 15
  sizeCaption: number = 12
  sizeMetric: number = 32
  sizeEyebrow: number = 11
  weightDisplay: number = 700
  weightTitle: number = 700
  weightHeading: number = 500
  weightBody: number = 400
  weightMetric: number = 700
  /** Applied to eyebrows only; 0 leaves the text alone. */
  eyebrowSpacing: number = 1
  /**
   * The typeface, where a preset wants one of its own.
   *
   * Empty means the system font, which is what five of the six use. Only the
   * two presets whose whole character is the typeface ask for another, and they
   * ask by generic family name so the device picks whatever it actually has.
   */
  fontFamily: string = ''

  // --- geometry ------------------------------------------------------------
  radiusCard: number = 14
  radiusControl: number = 10
  radiusSmall: number = 8
  borderWidth: number = 1

  padTight: number = 6
  padBase: number = 10
  padLoose: number = 16
  padCard: number = 14
  padRow: number = 6
  padGrid: number = 4
  padListX: number = 14
  padListY: number = 12

  gapTight: number = 4
  gapBase: number = 8
  gapLoose: number = 12
  /** How far one Section stands off the next. */
  gapSection: number = 14

  spacerSmall: number = 8
  spacerBase: number = 18
  spacerLarge: number = 32

  controlHeight: number = 44
  chipHeight: number = 36
}

/**
 * A fresh theme for a preset name. Called when the program's AppTheme changes,
 * never per node, so it may do as much work as it likes.
 */
export function makeTheme(preset: string): ResolvedTheme {
  let t = new ResolvedTheme()
  t.preset = 'clean'
  if (preset === 'soft') {
    // Warm neutrals, big radii, hardly any line work: the corners do the
    // separating that borders do elsewhere.
    t.preset = 'soft'
    t.primary = '#4C6EF5'
    t.primaryFill = '#E7EAFD'
    t.background = '#FBF9F7'
    t.surface = '#F4F0EC'
    t.surfaceRaised = '#FFFFFF'
    t.secondaryFill = '#EAE4DD'
    t.secondaryInk = '#4A4340'
    t.ink = '#2C2724'
    t.inkStrong = '#453E39'
    t.inkSoft = '#6E645D'
    t.inkMuted = '#857A70'
    t.line = '#E6DED6'
    t.lineSoft = '#EFE9E3'
    t.lineStrong = '#DDD3C9'
    t.successFill = '#E4F5E6'
    t.warningFill = '#FBF0DC'
    t.dangerFill = '#FBE7E4'
    t.radiusCard = 20
    t.radiusControl = 16
    t.radiusSmall = 12
    t.padTight = 10
    t.padBase = 14
    t.padLoose = 20
    t.padCard = 18
    t.padListX = 16
    t.padListY = 14
    t.gapBase = 10
    t.gapLoose = 16
    t.gapSection = 18
    t.weightHeading = 600
  } else if (preset === 'expressive') {
    // Saturated, tinted throughout, and heavy at the top of the scale. The
    // background is not white, which is most of why it reads as another app.
    t.preset = 'expressive'
    t.primary = '#6D28D9'
    t.primaryFill = '#EDE4FD'
    t.background = '#F6F2FC'
    t.surface = '#EDE6F8'
    t.surfaceRaised = '#FFFFFF'
    t.secondaryFill = '#E2D8F2'
    t.secondaryInk = '#3B2A5C'
    t.ink = '#1F1533'
    t.inkStrong = '#332553'
    t.inkSoft = '#5C4B7D'
    t.inkMuted = '#7A6B99'
    t.line = '#DCCFF2'
    t.lineSoft = '#E8DEF8'
    t.lineStrong = '#C9B6E8'
    t.success = '#059669'
    t.successInk = '#047857'
    t.successFill = '#D8F3E8'
    t.warning = '#D97706'
    t.warningInk = '#B45309'
    t.warningFill = '#FBEDD6'
    t.danger = '#DC2626'
    t.dangerInk = '#B91C1C'
    t.dangerFill = '#FBE0E0'
    t.pathDefault = '#3B2A5C'
    t.sizeDisplay = 36
    t.sizeTitle = 28
    t.sizeMetric = 38
    t.weightHeading = 700
    t.weightBody = 500
    t.radiusCard = 18
    t.radiusControl = 14
    t.padCard = 16
    t.gapSection = 18
  } else if (preset === 'editorial') {
    // Hierarchy carried by size and rule rather than by fill: surfaces are the
    // same colour as the page, and a hairline does the dividing.
    t.preset = 'editorial'
    t.fontFamily = 'serif'
    t.primary = '#1A1A1A'
    t.onPrimary = '#FFFFFF'
    t.primaryFill = '#F0EEE9'
    t.background = '#FDFCF9'
    t.surface = '#FDFCF9'
    t.surfaceRaised = '#FFFFFF'
    t.secondaryFill = '#EDEAE3'
    t.secondaryInk = '#1A1A1A'
    t.ink = '#111111'
    t.inkStrong = '#1A1A1A'
    t.inkSoft = '#55524B'
    t.inkMuted = '#8A857A'
    t.line = '#DAD5C9'
    t.lineSoft = '#E7E3D9'
    t.lineStrong = '#C9C3B4'
    t.successInk = '#1F6B37'
    t.successFill = '#EDF4EC'
    t.warningInk = '#8A4B0B'
    t.warningFill = '#F7F0E2'
    t.dangerInk = '#9B2226'
    t.dangerFill = '#F6E9E7'
    t.pathDefault = '#1A1A1A'
    t.sizeDisplay = 38
    t.sizeTitle = 30
    t.sizeHeading = 20
    t.sizeBody = 16
    t.sizeMetric = 34
    t.weightTitle = 700
    t.weightHeading = 600
    t.weightMetric = 500
    t.eyebrowSpacing = 2
    t.radiusCard = 4
    t.radiusControl = 4
    t.radiusSmall = 2
    t.padLoose = 20
    t.padCard = 16
    t.gapSection = 22
  } else if (preset === 'technical') {
    // Dense and outlined. Everything is a little smaller and a little tighter,
    // and the borders are visible, because this is the one for reading numbers.
    t.preset = 'technical'
    t.fontFamily = 'monospace'
    t.primary = '#0F766E'
    t.primaryFill = '#DCF0EE'
    t.background = '#FFFFFF'
    t.surface = '#F4F6F7'
    t.surfaceRaised = '#FFFFFF'
    t.secondaryFill = '#E3E8EA'
    t.secondaryInk = '#1F2A2E'
    t.ink = '#101820'
    t.inkStrong = '#26313A'
    t.inkSoft = '#55636D'
    t.inkMuted = '#7C8A94'
    t.line = '#C6D0D6'
    t.lineSoft = '#D8E0E4'
    t.lineStrong = '#AEBBC3'
    t.success = '#0F766E'
    t.successInk = '#0B5B55'
    t.successFill = '#DCF0EE'
    t.warning = '#B45309'
    t.warningInk = '#92400E'
    t.warningFill = '#F7EEDF'
    t.danger = '#B91C1C'
    t.dangerInk = '#991B1B'
    t.dangerFill = '#F7E3E3'
    t.pathDefault = '#26313A'
    t.sizeDisplay = 24
    t.sizeTitle = 20
    t.sizeHeading = 16
    t.sizeBody = 14
    t.sizeCaption = 11
    t.sizeMetric = 26
    t.sizeEyebrow = 10
    t.weightTitle = 600
    t.weightHeading = 600
    t.weightMetric = 600
    t.radiusCard = 6
    t.radiusControl = 6
    t.radiusSmall = 4
    t.padTight = 4
    t.padBase = 8
    t.padLoose = 12
    t.padCard = 10
    t.padListX = 10
    t.padListY = 8
    t.gapTight = 3
    t.gapBase = 6
    t.gapLoose = 9
    t.gapSection = 10
    t.spacerBase = 12
    t.spacerLarge = 22
    t.controlHeight = 40
    t.chipHeight = 32
  } else if (preset === 'playful') {
    // Pills, high chroma, plenty of air.
    t.preset = 'playful'
    t.primary = '#F0426B'
    t.primaryFill = '#FFE3EA'
    t.background = '#FFFCF5'
    t.surface = '#FFF1E6'
    t.surfaceRaised = '#FFFFFF'
    t.secondaryFill = '#FFE6CC'
    t.secondaryInk = '#7A3E12'
    t.ink = '#2B1B22'
    t.inkStrong = '#432A33'
    t.inkSoft = '#7A5C66'
    t.inkMuted = '#8F7681'
    t.line = '#FBD9C5'
    t.lineSoft = '#FFE8D9'
    t.lineStrong = '#F2C3A8'
    t.success = '#12A150'
    t.successInk = '#0E7A3D'
    t.successFill = '#DEF7E7'
    t.warning = '#F59E0B'
    t.warningInk = '#B45309'
    t.warningFill = '#FFF1D6'
    t.danger = '#F0426B'
    t.dangerInk = '#C2185B'
    t.dangerFill = '#FFE3EA'
    t.pathDefault = '#432A33'
    t.sizeDisplay = 34
    t.sizeTitle = 26
    t.sizeMetric = 36
    t.weightHeading = 700
    t.weightBody = 500
    t.radiusCard = 22
    t.radiusControl = 22
    t.radiusSmall = 14
    t.padTight = 8
    t.padBase = 12
    t.padLoose = 20
    t.padCard = 18
    t.gapBase = 10
    t.gapLoose = 16
    t.gapSection = 20
    t.spacerBase = 20
  }
  // By day the two are the same colour; applyDark is what parts them.
  t.primaryInk = t.primary
  return t
}

const HEX_DIGITS: string = '0123456789abcdefABCDEF'

/** '#rrggbb' and nothing else; anything shorter or stranger is ignored. */
export function isHexColor(s: string): boolean {
  if (s.length !== 7 || s.charAt(0) !== '#') { return false }
  for (let i = 1; i < 7; i++) {
    if (HEX_DIGITS.indexOf(s.charAt(i)) < 0) { return false }
  }
  return true
}

function channel(hex: string, at: number): number {
  return Number.parseInt(hex.substring(at, at + 2), 16)
}

function twoDigits(n: number): string {
  let v = Math.round(n)
  if (v < 0) { v = 0 }
  if (v > 255) { v = 255 }
  let s = v.toString(16).toUpperCase()
  return s.length < 2 ? '0' + s : s
}

/** `t` of the way from `a` to `b`: 0 is all a, 1 is all b. */
export function blendHex(a: string, b: string, t: number): string {
  if (!isHexColor(a) || !isHexColor(b)) { return a }
  return '#' +
    twoDigits(channel(a, 1) + (channel(b, 1) - channel(a, 1)) * t) +
    twoDigits(channel(a, 3) + (channel(b, 3) - channel(a, 3)) * t) +
    twoDigits(channel(a, 5) + (channel(b, 5) - channel(a, 5)) * t)
}

/**
 * White or near-black, whichever stays legible on the given fill. Perceived
 * brightness, not the plain average -- green reads far lighter than blue at the
 * same numeric value, and a plain average puts white text on a yellow button.
 */
export function readableInk(fill: string): string {
  if (!isHexColor(fill)) { return '#FFFFFF' }
  let lum = (channel(fill, 1) * 299 + channel(fill, 3) * 587 + channel(fill, 5) * 114) / 1000
  return lum > 150 ? '#1A1A1A' : '#FFFFFF'
}

/** How bright a colour reads, weighted the way an eye weights it. */
function luminance(hex: string): number {
  if (!isHexColor(hex)) { return 0 }
  return (channel(hex, 1) * 299 + channel(hex, 3) * 587 + channel(hex, 5) * 114) / 1000
}

function lighten(hex: string, amount: number): string {
  return blendHex(hex, '#FFFFFF', amount)
}

/**
 * The same preset after dark.
 *
 * Not an inversion. Inverting a palette gives grey text on grey boxes, because
 * the light palette's separations were chosen against white and none of them
 * survive being flipped. What each preset keeps is its *hue*: the surfaces below
 * are the preset's own colour taken down to near-black, so soft stays warm,
 * expressive stays violet and technical stays cold, and the six remain as
 * different from one another as they are by day.
 *
 * Only the structural colours are written out. Everything else is derived, so
 * a tone fill is always the tone sunk into this preset's surface rather than a
 * value picked twice and drifting apart.
 */
function applyDark(t: ResolvedTheme, preset: string): void {
  if (preset === 'soft') {
    t.background = '#17140F'; t.surface = '#211C15'; t.surfaceRaised = '#2B241C'
    t.line = '#3A3229'; t.lineSoft = '#2F2822'; t.lineStrong = '#4A4034'
    t.ink = '#F3ECE1'; t.inkStrong = '#E3D9CA'; t.inkSoft = '#B6A996'; t.inkMuted = '#8A7E6D'
  } else if (preset === 'expressive') {
    t.background = '#140F20'; t.surface = '#1D1630'; t.surfaceRaised = '#261D3E'
    t.line = '#382B54'; t.lineSoft = '#2B2143'; t.lineStrong = '#4A3A6B'
    t.ink = '#EFE8FA'; t.inkStrong = '#DDD3EE'; t.inkSoft = '#AFA2C8'; t.inkMuted = '#8477A0'
  } else if (preset === 'editorial') {
    t.background = '#101010'; t.surface = '#101010'; t.surfaceRaised = '#1A1A1A'
    t.line = '#2E2E2C'; t.lineSoft = '#242422'; t.lineStrong = '#3E3E3A'
    t.ink = '#F3F1EA'; t.inkStrong = '#E4E1D8'; t.inkSoft = '#ADA99C'; t.inkMuted = '#807C70'
  } else if (preset === 'technical') {
    t.background = '#0B0F11'; t.surface = '#131A1D'; t.surfaceRaised = '#182126'
    t.line = '#26323A'; t.lineSoft = '#1D272C'; t.lineStrong = '#35444E'
    t.ink = '#E4EDF2'; t.inkStrong = '#D0DCE3'; t.inkSoft = '#94A5B0'; t.inkMuted = '#6E7F8A'
  } else if (preset === 'playful') {
    t.background = '#1A1114'; t.surface = '#241A1E'; t.surfaceRaised = '#2F2228'
    t.line = '#402F37'; t.lineSoft = '#32252B'; t.lineStrong = '#523B45'
    t.ink = '#FCEDF1'; t.inkStrong = '#F0DCE2'; t.inkSoft = '#C0A3AD'; t.inkMuted = '#967A84'
  } else {
    t.background = '#0E1116'; t.surface = '#161B22'; t.surfaceRaised = '#1C242F'
    t.line = '#2A3440'; t.lineSoft = '#212933'; t.lineStrong = '#3A4756'
    t.ink = '#E6EDF3'; t.inkStrong = '#D2DBE4'; t.inkSoft = '#9FADBC'; t.inkMuted = '#78889A'
  }
  t.surfaceDisabled = t.lineSoft
  t.inkDisabled = t.inkMuted

  // A tone that was chosen to read on white has to be brought up to read on
  // near-black. Editorial's primary is very nearly black by day, so lightening
  // it by a fifth would leave it invisible -- anything this dark is taken most
  // of the way to white instead.
  if (luminance(t.primary) < 70) { t.primary = lighten(t.primary, 0.82) }
  // Text and rules in the accent colour have to clear the surface behind them,
  // which the button's fill colour does not do after dark.
  t.primaryInk = luminance(t.primary) < 150 ? lighten(t.primary, 0.45) : t.primary
  t.success = lighten(t.success, 0.26)
  t.warning = lighten(t.warning, 0.30)
  t.danger = lighten(t.danger, 0.26)
  t.successInk = t.success
  t.warningInk = t.warning
  t.dangerInk = t.danger
  t.onPrimary = readableInk(t.primary)

  // Every fill is its tone sunk into this preset's own surface.
  t.primaryFill = blendHex(t.primaryInk, t.surface, 0.84)
  t.successFill = blendHex(t.success, t.surface, 0.84)
  t.warningFill = blendHex(t.warning, t.surface, 0.84)
  t.dangerFill = blendHex(t.danger, t.surface, 0.84)

  t.secondaryFill = t.surfaceRaised
  t.secondaryInk = t.ink
  t.pathDefault = t.inkStrong
  t.pathMuted = t.inkMuted
}

/**
 * The preset, with the program's own seed colour folded in when it gave one.
 *
 * The seed replaces the primary and its container is derived rather than asked
 * for: a model that picks one brand colour should not also have to pick the
 * five tints that go with it, and picking them by hand is how the tints end up
 * not matching the colour.
 */
export function resolveTheme(preset: string, primaryHex: string, dark: boolean): ResolvedTheme {
  let t = makeTheme(preset)
  if (isHexColor(primaryHex)) {
    t.primary = primaryHex
    t.primaryInk = primaryHex
    t.onPrimary = readableInk(primaryHex)
    t.primaryFill = blendHex(primaryHex, t.background, 0.88)
  }
  // After the seed, so a program's own colour is carried into the dark palette
  // and lightened with it rather than being overwritten by the preset's.
  if (dark) { applyDark(t, t.preset) }
  return t
}

// --- what the renderer asks, per node ---------------------------------------
// Table lookups only. These run once per node per frame, so nothing here
// parses, blends or allocates.

/** Background of a container asking for 'surface' or 'accent'; else transparent. */
export function containerFill(t: ResolvedTheme, style: string): string {
  if (style === 'surface') { return t.surface }
  if (style === 'accent') { return t.primaryFill }
  return '#00000000'
}

/** The tinted fill behind a card, list row or banner. */
export function toneFill(t: ResolvedTheme, style: string, fallback: string): string {
  if (style === 'accent') { return t.primaryFill }
  if (style === 'success') { return t.successFill }
  if (style === 'warning') { return t.warningFill }
  if (style === 'danger') { return t.dangerFill }
  return fallback
}

/** The saturated version of a tone: a rail, a bar, a border. */
export function toneEdge(t: ResolvedTheme, style: string, fallback: string): string {
  if (style === 'accent') { return t.primaryInk }
  if (style === 'success') { return t.success }
  if (style === 'warning') { return t.warning }
  if (style === 'danger') { return t.danger }
  return fallback
}

/** Text in a tone, darkened enough to read at body size. */
export function toneInk(t: ResolvedTheme, style: string, fallback: string): string {
  if (style === 'accent') { return t.primaryInk }
  if (style === 'success') { return t.successInk }
  if (style === 'warning') { return t.warningInk }
  if (style === 'danger') { return t.dangerInk }
  if (style === 'muted') { return t.inkMuted }
  return fallback
}

export function textSize(t: ResolvedTheme, style: string): number {
  if (style === 'display') { return t.sizeDisplay }
  if (style === 'title') { return t.sizeTitle }
  if (style === 'heading') { return t.sizeHeading }
  if (style === 'metric') { return t.sizeMetric }
  if (style === 'caption') { return t.sizeCaption }
  if (style === 'eyebrow') { return t.sizeEyebrow }
  return t.sizeBody
}

export function textWeight(t: ResolvedTheme, style: string): number {
  if (style === 'display') { return t.weightDisplay }
  if (style === 'title') { return t.weightTitle }
  if (style === 'heading') { return t.weightHeading }
  if (style === 'metric') { return t.weightMetric }
  if (style === 'eyebrow') { return t.weightHeading }
  return t.weightBody
}

export function textInk(t: ResolvedTheme, style: string): string {
  // 'caption' is deliberately not muted here. It was drawn in the ink colour
  // before this module existed, and a caption quietly turning grey would be a
  // visual change to every program already written. A caption that wants to be
  // quiet asks for 'muted'.
  if (style === 'eyebrow') { return t.inkMuted }
  return toneInk(t, style, t.ink)
}

export function buttonFill(t: ResolvedTheme, style: string): string {
  if (style === 'success') { return t.success }
  if (style === 'danger') { return t.danger }
  if (style === 'secondary') { return t.secondaryFill }
  return t.primary
}

export function buttonInk(t: ResolvedTheme, style: string): string {
  if (style === 'secondary') { return t.secondaryInk }
  if (style === 'success') { return readableInk(t.success) }
  if (style === 'danger') { return readableInk(t.danger) }
  return t.onPrimary
}

export function pathFill(t: ResolvedTheme, style: string): string {
  if (style === 'accent') { return t.primary }
  if (style === 'success') { return t.success }
  if (style === 'warning') { return t.warning }
  if (style === 'danger') { return t.danger }
  if (style === 'muted') { return t.pathMuted }
  if (style === 'light') { return '#FFFFFF' }
  return t.pathDefault
}

/** Padding for a container whose style names a density. */
export function densityPad(t: ResolvedTheme, style: string): number {
  if (style === 'compact') { return t.padTight }
  if (style === 'spacious') { return t.padLoose }
  return t.padBase
}

/** The gap between a container's children, for the same density names. */
export function densityGap(t: ResolvedTheme, style: string): number {
  if (style === 'compact') { return t.gapTight }
  if (style === 'spacious') { return t.gapLoose }
  // 'joined' is for children that have to read as one thing: the two ui.IntText
  // of a clock are "21:09" only if nothing sits between them.
  if (style === 'joined') { return 0 }
  return t.gapBase
}

export function spacerSize(t: ResolvedTheme, style: string): number {
  if (style === 'none') { return 0 }
  if (style === 'small') { return t.spacerSmall }
  if (style === 'large') { return t.spacerLarge }
  return t.spacerBase
}
