export const ICON_STROKE: string = '8px';
export const ICON_VIEWPORT: string = '100px';
export const ICON_ORIGIN: string = '0px';
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
]);
export function iconNames(): string[] {
    let a101: string[] = [];
    ICONS.forEach((b101: string, c101: string) => { a101.push(c101); });
    return a101;
}
export function iconPath(y100: string): string {
    let z100 = ICONS.get(y100);
    return z100 !== undefined ? z100 : '';
}
