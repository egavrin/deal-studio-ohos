export const PRESET_NAMES: string[] = [
    'clean', 'soft', 'expressive', 'editorial', 'technical', 'playful'
];
export class ResolvedTheme {
    preset: string = 'clean';
    primary: string = '#007DFF';
    onPrimary: string = '#FFFFFF';
    primaryFill: string = '#EBF0FF';
    primaryInk: string = '#007DFF';
    secondaryFill: string = '#E0E0E0';
    secondaryInk: string = '#333333';
    background: string = '#FFFFFF';
    surface: string = '#F3F6FA';
    surfaceRaised: string = '#FFFFFF';
    surfaceDisabled: string = '#F5F5F5';
    ink: string = '#000000';
    inkStrong: string = '#333333';
    inkSoft: string = '#666666';
    inkMuted: string = '#888888';
    inkDisabled: string = '#CCCCCC';
    line: string = '#D8E1ED';
    lineSoft: string = '#E4EAF2';
    lineStrong: string = '#CBD6E4';
    success: string = '#4CAF50';
    successInk: string = '#2E7D32';
    successFill: string = '#E8F8E8';
    warning: string = '#E65100';
    warningInk: string = '#E65100';
    warningFill: string = '#FFF8E0';
    danger: string = '#F44336';
    dangerInk: string = '#C62828';
    dangerFill: string = '#FFECEC';
    pathDefault: string = '#37474F';
    pathMuted: string = '#B0BEC5';
    sizeDisplay: number = 30;
    sizeTitle: number = 24;
    sizeHeading: number = 18;
    sizeBody: number = 15;
    sizeCaption: number = 12;
    sizeMetric: number = 32;
    sizeEyebrow: number = 11;
    weightDisplay: number = 700;
    weightTitle: number = 700;
    weightHeading: number = 500;
    weightBody: number = 400;
    weightMetric: number = 700;
    eyebrowSpacing: number = 1;
    fontFamily: string = '';
    radiusCard: number = 14;
    radiusControl: number = 10;
    radiusSmall: number = 8;
    borderWidth: number = 1;
    padTight: number = 6;
    padBase: number = 10;
    padLoose: number = 16;
    padCard: number = 14;
    padRow: number = 6;
    padGrid: number = 4;
    padListX: number = 14;
    padListY: number = 12;
    gapTight: number = 4;
    gapBase: number = 8;
    gapLoose: number = 12;
    gapSection: number = 14;
    spacerSmall: number = 8;
    spacerBase: number = 18;
    spacerLarge: number = 32;
    controlHeight: number = 44;
    chipHeight: number = 36;
}
export function makeTheme(c176: string): ResolvedTheme {
    let d176 = new ResolvedTheme();
    d176.preset = 'clean';
    if (c176 === 'soft') {
        d176.preset = 'soft';
        d176.primary = '#4C6EF5';
        d176.primaryFill = '#E7EAFD';
        d176.background = '#FBF9F7';
        d176.surface = '#F4F0EC';
        d176.surfaceRaised = '#FFFFFF';
        d176.secondaryFill = '#EAE4DD';
        d176.secondaryInk = '#4A4340';
        d176.ink = '#2C2724';
        d176.inkStrong = '#453E39';
        d176.inkSoft = '#6E645D';
        d176.inkMuted = '#857A70';
        d176.line = '#E6DED6';
        d176.lineSoft = '#EFE9E3';
        d176.lineStrong = '#DDD3C9';
        d176.successFill = '#E4F5E6';
        d176.warningFill = '#FBF0DC';
        d176.dangerFill = '#FBE7E4';
        d176.radiusCard = 20;
        d176.radiusControl = 16;
        d176.radiusSmall = 12;
        d176.padTight = 10;
        d176.padBase = 14;
        d176.padLoose = 20;
        d176.padCard = 18;
        d176.padListX = 16;
        d176.padListY = 14;
        d176.gapBase = 10;
        d176.gapLoose = 16;
        d176.gapSection = 18;
        d176.weightHeading = 600;
    }
    else if (c176 === 'expressive') {
        d176.preset = 'expressive';
        d176.primary = '#6D28D9';
        d176.primaryFill = '#EDE4FD';
        d176.background = '#F6F2FC';
        d176.surface = '#EDE6F8';
        d176.surfaceRaised = '#FFFFFF';
        d176.secondaryFill = '#E2D8F2';
        d176.secondaryInk = '#3B2A5C';
        d176.ink = '#1F1533';
        d176.inkStrong = '#332553';
        d176.inkSoft = '#5C4B7D';
        d176.inkMuted = '#7A6B99';
        d176.line = '#DCCFF2';
        d176.lineSoft = '#E8DEF8';
        d176.lineStrong = '#C9B6E8';
        d176.success = '#059669';
        d176.successInk = '#047857';
        d176.successFill = '#D8F3E8';
        d176.warning = '#D97706';
        d176.warningInk = '#B45309';
        d176.warningFill = '#FBEDD6';
        d176.danger = '#DC2626';
        d176.dangerInk = '#B91C1C';
        d176.dangerFill = '#FBE0E0';
        d176.pathDefault = '#3B2A5C';
        d176.sizeDisplay = 36;
        d176.sizeTitle = 28;
        d176.sizeMetric = 38;
        d176.weightHeading = 700;
        d176.weightBody = 500;
        d176.radiusCard = 18;
        d176.radiusControl = 14;
        d176.padCard = 16;
        d176.gapSection = 18;
    }
    else if (c176 === 'editorial') {
        d176.preset = 'editorial';
        d176.fontFamily = 'serif';
        d176.primary = '#1A1A1A';
        d176.onPrimary = '#FFFFFF';
        d176.primaryFill = '#F0EEE9';
        d176.background = '#FDFCF9';
        d176.surface = '#FDFCF9';
        d176.surfaceRaised = '#FFFFFF';
        d176.secondaryFill = '#EDEAE3';
        d176.secondaryInk = '#1A1A1A';
        d176.ink = '#111111';
        d176.inkStrong = '#1A1A1A';
        d176.inkSoft = '#55524B';
        d176.inkMuted = '#8A857A';
        d176.line = '#DAD5C9';
        d176.lineSoft = '#E7E3D9';
        d176.lineStrong = '#C9C3B4';
        d176.successInk = '#1F6B37';
        d176.successFill = '#EDF4EC';
        d176.warningInk = '#8A4B0B';
        d176.warningFill = '#F7F0E2';
        d176.dangerInk = '#9B2226';
        d176.dangerFill = '#F6E9E7';
        d176.pathDefault = '#1A1A1A';
        d176.sizeDisplay = 38;
        d176.sizeTitle = 30;
        d176.sizeHeading = 20;
        d176.sizeBody = 16;
        d176.sizeMetric = 34;
        d176.weightTitle = 700;
        d176.weightHeading = 600;
        d176.weightMetric = 500;
        d176.eyebrowSpacing = 2;
        d176.radiusCard = 4;
        d176.radiusControl = 4;
        d176.radiusSmall = 2;
        d176.padLoose = 20;
        d176.padCard = 16;
        d176.gapSection = 22;
    }
    else if (c176 === 'technical') {
        d176.preset = 'technical';
        d176.fontFamily = 'monospace';
        d176.primary = '#0F766E';
        d176.primaryFill = '#DCF0EE';
        d176.background = '#FFFFFF';
        d176.surface = '#F4F6F7';
        d176.surfaceRaised = '#FFFFFF';
        d176.secondaryFill = '#E3E8EA';
        d176.secondaryInk = '#1F2A2E';
        d176.ink = '#101820';
        d176.inkStrong = '#26313A';
        d176.inkSoft = '#55636D';
        d176.inkMuted = '#7C8A94';
        d176.line = '#C6D0D6';
        d176.lineSoft = '#D8E0E4';
        d176.lineStrong = '#AEBBC3';
        d176.success = '#0F766E';
        d176.successInk = '#0B5B55';
        d176.successFill = '#DCF0EE';
        d176.warning = '#B45309';
        d176.warningInk = '#92400E';
        d176.warningFill = '#F7EEDF';
        d176.danger = '#B91C1C';
        d176.dangerInk = '#991B1B';
        d176.dangerFill = '#F7E3E3';
        d176.pathDefault = '#26313A';
        d176.sizeDisplay = 24;
        d176.sizeTitle = 20;
        d176.sizeHeading = 16;
        d176.sizeBody = 14;
        d176.sizeCaption = 11;
        d176.sizeMetric = 26;
        d176.sizeEyebrow = 10;
        d176.weightTitle = 600;
        d176.weightHeading = 600;
        d176.weightMetric = 600;
        d176.radiusCard = 6;
        d176.radiusControl = 6;
        d176.radiusSmall = 4;
        d176.padTight = 4;
        d176.padBase = 8;
        d176.padLoose = 12;
        d176.padCard = 10;
        d176.padListX = 10;
        d176.padListY = 8;
        d176.gapTight = 3;
        d176.gapBase = 6;
        d176.gapLoose = 9;
        d176.gapSection = 10;
        d176.spacerBase = 12;
        d176.spacerLarge = 22;
        d176.controlHeight = 40;
        d176.chipHeight = 32;
    }
    else if (c176 === 'playful') {
        d176.preset = 'playful';
        d176.primary = '#F0426B';
        d176.primaryFill = '#FFE3EA';
        d176.background = '#FFFCF5';
        d176.surface = '#FFF1E6';
        d176.surfaceRaised = '#FFFFFF';
        d176.secondaryFill = '#FFE6CC';
        d176.secondaryInk = '#7A3E12';
        d176.ink = '#2B1B22';
        d176.inkStrong = '#432A33';
        d176.inkSoft = '#7A5C66';
        d176.inkMuted = '#8F7681';
        d176.line = '#FBD9C5';
        d176.lineSoft = '#FFE8D9';
        d176.lineStrong = '#F2C3A8';
        d176.success = '#12A150';
        d176.successInk = '#0E7A3D';
        d176.successFill = '#DEF7E7';
        d176.warning = '#F59E0B';
        d176.warningInk = '#B45309';
        d176.warningFill = '#FFF1D6';
        d176.danger = '#F0426B';
        d176.dangerInk = '#C2185B';
        d176.dangerFill = '#FFE3EA';
        d176.pathDefault = '#432A33';
        d176.sizeDisplay = 34;
        d176.sizeTitle = 26;
        d176.sizeMetric = 36;
        d176.weightHeading = 700;
        d176.weightBody = 500;
        d176.radiusCard = 22;
        d176.radiusControl = 22;
        d176.radiusSmall = 14;
        d176.padTight = 8;
        d176.padBase = 12;
        d176.padLoose = 20;
        d176.padCard = 18;
        d176.gapBase = 10;
        d176.gapLoose = 16;
        d176.gapSection = 20;
        d176.spacerBase = 20;
    }
    d176.primaryInk = d176.primary;
    return d176;
}
const HEX_DIGITS: string = '0123456789abcdefABCDEF';
export function isHexColor(a176: string): boolean {
    if (a176.length !== 7 || a176.charAt(0) !== '#') {
        return false;
    }
    for (let b176 = 1; b176 < 7; b176++) {
        if (HEX_DIGITS.indexOf(a176.charAt(b176)) < 0) {
            return false;
        }
    }
    return true;
}
function channel(y175: string, z175: number): number {
    return Number.parseInt(y175.substring(z175, z175 + 2), 16);
}
function twoDigits(v175: number): string {
    let w175 = Math.round(v175);
    if (w175 < 0) {
        w175 = 0;
    }
    if (w175 > 255) {
        w175 = 255;
    }
    let x175 = w175.toString(16).toUpperCase();
    return x175.length < 2 ? '0' + x175 : x175;
}
export function blendHex(s175: string, t175: string, u175: number): string {
    if (!isHexColor(s175) || !isHexColor(t175)) {
        return s175;
    }
    return '#' +
        twoDigits(channel(s175, 1) + (channel(t175, 1) - channel(s175, 1)) * u175) +
        twoDigits(channel(s175, 3) + (channel(t175, 3) - channel(s175, 3)) * u175) +
        twoDigits(channel(s175, 5) + (channel(t175, 5) - channel(s175, 5)) * u175);
}
export function readableInk(q175: string): string {
    if (!isHexColor(q175)) {
        return '#FFFFFF';
    }
    let r175 = (channel(q175, 1) * 299 + channel(q175, 3) * 587 + channel(q175, 5) * 114) / 1000;
    return r175 > 150 ? '#1A1A1A' : '#FFFFFF';
}
function luminance(p175: string): number {
    if (!isHexColor(p175)) {
        return 0;
    }
    return (channel(p175, 1) * 299 + channel(p175, 3) * 587 + channel(p175, 5) * 114) / 1000;
}
function lighten(n175: string, o175: number): string {
    return blendHex(n175, '#FFFFFF', o175);
}
function applyDark(l175: ResolvedTheme, m175: string): void {
    if (m175 === 'soft') {
        l175.background = '#17140F';
        l175.surface = '#211C15';
        l175.surfaceRaised = '#2B241C';
        l175.line = '#3A3229';
        l175.lineSoft = '#2F2822';
        l175.lineStrong = '#4A4034';
        l175.ink = '#F3ECE1';
        l175.inkStrong = '#E3D9CA';
        l175.inkSoft = '#B6A996';
        l175.inkMuted = '#8A7E6D';
    }
    else if (m175 === 'expressive') {
        l175.background = '#140F20';
        l175.surface = '#1D1630';
        l175.surfaceRaised = '#261D3E';
        l175.line = '#382B54';
        l175.lineSoft = '#2B2143';
        l175.lineStrong = '#4A3A6B';
        l175.ink = '#EFE8FA';
        l175.inkStrong = '#DDD3EE';
        l175.inkSoft = '#AFA2C8';
        l175.inkMuted = '#8477A0';
    }
    else if (m175 === 'editorial') {
        l175.background = '#101010';
        l175.surface = '#101010';
        l175.surfaceRaised = '#1A1A1A';
        l175.line = '#2E2E2C';
        l175.lineSoft = '#242422';
        l175.lineStrong = '#3E3E3A';
        l175.ink = '#F3F1EA';
        l175.inkStrong = '#E4E1D8';
        l175.inkSoft = '#ADA99C';
        l175.inkMuted = '#807C70';
    }
    else if (m175 === 'technical') {
        l175.background = '#0B0F11';
        l175.surface = '#131A1D';
        l175.surfaceRaised = '#182126';
        l175.line = '#26323A';
        l175.lineSoft = '#1D272C';
        l175.lineStrong = '#35444E';
        l175.ink = '#E4EDF2';
        l175.inkStrong = '#D0DCE3';
        l175.inkSoft = '#94A5B0';
        l175.inkMuted = '#6E7F8A';
    }
    else if (m175 === 'playful') {
        l175.background = '#1A1114';
        l175.surface = '#241A1E';
        l175.surfaceRaised = '#2F2228';
        l175.line = '#402F37';
        l175.lineSoft = '#32252B';
        l175.lineStrong = '#523B45';
        l175.ink = '#FCEDF1';
        l175.inkStrong = '#F0DCE2';
        l175.inkSoft = '#C0A3AD';
        l175.inkMuted = '#967A84';
    }
    else {
        l175.background = '#0E1116';
        l175.surface = '#161B22';
        l175.surfaceRaised = '#1C242F';
        l175.line = '#2A3440';
        l175.lineSoft = '#212933';
        l175.lineStrong = '#3A4756';
        l175.ink = '#E6EDF3';
        l175.inkStrong = '#D2DBE4';
        l175.inkSoft = '#9FADBC';
        l175.inkMuted = '#78889A';
    }
    l175.surfaceDisabled = l175.lineSoft;
    l175.inkDisabled = l175.inkMuted;
    if (luminance(l175.primary) < 70) {
        l175.primary = lighten(l175.primary, 0.82);
    }
    l175.primaryInk = luminance(l175.primary) < 150 ? lighten(l175.primary, 0.45) : l175.primary;
    l175.success = lighten(l175.success, 0.26);
    l175.warning = lighten(l175.warning, 0.30);
    l175.danger = lighten(l175.danger, 0.26);
    l175.successInk = l175.success;
    l175.warningInk = l175.warning;
    l175.dangerInk = l175.danger;
    l175.onPrimary = readableInk(l175.primary);
    l175.primaryFill = blendHex(l175.primaryInk, l175.surface, 0.84);
    l175.successFill = blendHex(l175.success, l175.surface, 0.84);
    l175.warningFill = blendHex(l175.warning, l175.surface, 0.84);
    l175.dangerFill = blendHex(l175.danger, l175.surface, 0.84);
    l175.secondaryFill = l175.surfaceRaised;
    l175.secondaryInk = l175.ink;
    l175.pathDefault = l175.inkStrong;
    l175.pathMuted = l175.inkMuted;
}
export function resolveTheme(h175: string, i175: string, j175: boolean): ResolvedTheme {
    let k175 = makeTheme(h175);
    if (isHexColor(i175)) {
        k175.primary = i175;
        k175.primaryInk = i175;
        k175.onPrimary = readableInk(i175);
        k175.primaryFill = blendHex(i175, k175.background, 0.88);
    }
    if (j175) {
        applyDark(k175, k175.preset);
    }
    return k175;
}
export function containerFill(f175: ResolvedTheme, g175: string): string {
    if (g175 === 'surface') {
        return f175.surface;
    }
    if (g175 === 'accent') {
        return f175.primaryFill;
    }
    return '#00000000';
}
export function toneFill(c175: ResolvedTheme, d175: string, e175: string): string {
    if (d175 === 'accent') {
        return c175.primaryFill;
    }
    if (d175 === 'success') {
        return c175.successFill;
    }
    if (d175 === 'warning') {
        return c175.warningFill;
    }
    if (d175 === 'danger') {
        return c175.dangerFill;
    }
    return e175;
}
export function toneEdge(z174: ResolvedTheme, a175: string, b175: string): string {
    if (a175 === 'accent') {
        return z174.primaryInk;
    }
    if (a175 === 'success') {
        return z174.success;
    }
    if (a175 === 'warning') {
        return z174.warning;
    }
    if (a175 === 'danger') {
        return z174.danger;
    }
    return b175;
}
export function toneInk(w174: ResolvedTheme, x174: string, y174: string): string {
    if (x174 === 'accent') {
        return w174.primaryInk;
    }
    if (x174 === 'success') {
        return w174.successInk;
    }
    if (x174 === 'warning') {
        return w174.warningInk;
    }
    if (x174 === 'danger') {
        return w174.dangerInk;
    }
    if (x174 === 'muted') {
        return w174.inkMuted;
    }
    return y174;
}
export function textSize(u174: ResolvedTheme, v174: string): number {
    if (v174 === 'display') {
        return u174.sizeDisplay;
    }
    if (v174 === 'title') {
        return u174.sizeTitle;
    }
    if (v174 === 'heading') {
        return u174.sizeHeading;
    }
    if (v174 === 'metric') {
        return u174.sizeMetric;
    }
    if (v174 === 'caption') {
        return u174.sizeCaption;
    }
    if (v174 === 'eyebrow') {
        return u174.sizeEyebrow;
    }
    return u174.sizeBody;
}
export function textWeight(s174: ResolvedTheme, t174: string): number {
    if (t174 === 'display') {
        return s174.weightDisplay;
    }
    if (t174 === 'title') {
        return s174.weightTitle;
    }
    if (t174 === 'heading') {
        return s174.weightHeading;
    }
    if (t174 === 'metric') {
        return s174.weightMetric;
    }
    if (t174 === 'eyebrow') {
        return s174.weightHeading;
    }
    return s174.weightBody;
}
export function textInk(q174: ResolvedTheme, r174: string): string {
    if (r174 === 'eyebrow') {
        return q174.inkMuted;
    }
    return toneInk(q174, r174, q174.ink);
}
export function buttonFill(o174: ResolvedTheme, p174: string): string {
    if (p174 === 'success') {
        return o174.success;
    }
    if (p174 === 'danger') {
        return o174.danger;
    }
    if (p174 === 'secondary') {
        return o174.secondaryFill;
    }
    return o174.primary;
}
export function buttonInk(m174: ResolvedTheme, n174: string): string {
    if (n174 === 'secondary') {
        return m174.secondaryInk;
    }
    if (n174 === 'success') {
        return readableInk(m174.success);
    }
    if (n174 === 'danger') {
        return readableInk(m174.danger);
    }
    return m174.onPrimary;
}
export function pathFill(k174: ResolvedTheme, l174: string): string {
    if (l174 === 'accent') {
        return k174.primary;
    }
    if (l174 === 'success') {
        return k174.success;
    }
    if (l174 === 'warning') {
        return k174.warning;
    }
    if (l174 === 'danger') {
        return k174.danger;
    }
    if (l174 === 'muted') {
        return k174.pathMuted;
    }
    if (l174 === 'light') {
        return '#FFFFFF';
    }
    return k174.pathDefault;
}
export function densityPad(i174: ResolvedTheme, j174: string): number {
    if (j174 === 'compact') {
        return i174.padTight;
    }
    if (j174 === 'spacious') {
        return i174.padLoose;
    }
    return i174.padBase;
}
export function densityGap(g174: ResolvedTheme, h174: string): number {
    if (h174 === 'compact') {
        return g174.gapTight;
    }
    if (h174 === 'spacious') {
        return g174.gapLoose;
    }
    if (h174 === 'joined') {
        return 0;
    }
    return g174.gapBase;
}
export function spacerSize(e174: ResolvedTheme, f174: string): number {
    if (f174 === 'none') {
        return 0;
    }
    if (f174 === 'small') {
        return e174.spacerSmall;
    }
    if (f174 === 'large') {
        return e174.spacerLarge;
    }
    return e174.spacerBase;
}
