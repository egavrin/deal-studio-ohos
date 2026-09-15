/**
 * Device-local settings: the DeepSeek API key and the model to call.
 *
 * The key is written by EntryAbility from a launch parameter, so it never has
 * to be typed on the phone:
 *
 *   hdc shell aa start -a EntryAbility -b com.vera.probe.dyn \
 *     --ps deepseekKey sk-...
 *
 * It lives in the app sandbox ({filesDir}/vera/settings.json), not in the HAP
 * and not in this repository. Only maskedKey() is ever shown or logged.
 */

import fs from '@ohos.file.fs'

export const DEFAULT_DEEPSEEK_BASE_URL: string = 'https://api.deepseek.com'
export const DEFAULT_DEEPSEEK_MODEL: string = 'deepseek-flash'

function readText(path: string): string {
  try {
    let stat = fs.statSync(path)
    if (stat.size === 0) { return '' }
    return fs.readTextSync(path)
  } catch (_e) {
    return ''
  }
}

function writeText(path: string, content: string): void {
  let file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
  fs.writeSync(file.fd, content)
  fs.closeSync(file)
}

export class SettingsStore {
  private root: string = ''
  private apiKey: string = ''
  private model: string = DEFAULT_DEEPSEEK_MODEL
  private baseUrl: string = DEFAULT_DEEPSEEK_BASE_URL
  private loaded: boolean = false

  init(filesDir: string): void {
    this.root = filesDir + '/vera'
    try { fs.mkdirSync(this.root, true) } catch (_e) {}
    this.load()
  }

  isReady(): boolean { return this.root.length > 0 }

  private path(): string { return this.root + '/settings.json' }

  private load(): void {
    let text = readText(this.path())
    if (text.length > 0) {
      try {
        let obj = JSON.parse(text) as Record<string, Object>
        this.apiKey = (obj['apiKey'] as string) || ''
        this.model = (obj['model'] as string) || DEFAULT_DEEPSEEK_MODEL
        this.baseUrl = (obj['baseUrl'] as string) || DEFAULT_DEEPSEEK_BASE_URL
      } catch (_e) {}
    }
    this.loaded = true
  }

  private save(): void {
    if (this.root.length === 0) { return }
    let obj: Record<string, Object> = {}
    obj['apiKey'] = this.apiKey
    obj['model'] = this.model
    obj['baseUrl'] = this.baseUrl
    try { writeText(this.path(), JSON.stringify(obj)) } catch (_e) {}
  }

  getApiKey(): string {
    if (!this.loaded) { this.load() }
    return this.apiKey
  }

  hasApiKey(): boolean { return this.getApiKey().length > 0 }

  setApiKey(key: string): void {
    this.apiKey = key.trim()
    this.save()
  }

  getModel(): string {
    if (!this.loaded) { this.load() }
    return this.model.length > 0 ? this.model : DEFAULT_DEEPSEEK_MODEL
  }

  setModel(model: string): void {
    this.model = model.trim()
    this.save()
  }

  getBaseUrl(): string {
    if (!this.loaded) { this.load() }
    return this.baseUrl.length > 0 ? this.baseUrl : DEFAULT_DEEPSEEK_BASE_URL
  }

  /** 'sk-...abcd' — enough to tell whether the key arrived, useless if leaked. */
  maskedKey(): string {
    let key = this.getApiKey()
    if (key.length === 0) { return '(no key)' }
    if (key.length <= 7) { return 'sk-...' }
    return key.substring(0, 3) + '...' + key.substring(key.length - 4)
  }
}

export const settings: SettingsStore = new SettingsStore()
