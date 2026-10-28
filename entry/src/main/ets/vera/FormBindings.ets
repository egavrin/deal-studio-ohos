import fs from '@ohos.file.fs'

/** Reload on every operation: the UI and form extension run in different processes. */
export class FormBindings {
  private path: string = ''

  init(filesDir: string): void {
    let root = filesDir + '/vera'
    try { fs.mkdirSync(root, true) } catch (_e) {}
    this.path = root + '/forms.json'
  }

  private read(): Record<string, string> {
    if (this.path.length === 0) { throw new Error('Form bindings are not initialised') }
    try { return JSON.parse(fs.readTextSync(this.path)) as Record<string, string> } catch (_e) { return {} }
  }

  projectFor(formId: string): string { return this.read()[formId] || '' }

  formsFor(projectId: string): string[] {
    let entries = this.read()
    return Object.keys(entries).filter((id: string): boolean => entries[id] === projectId)
  }

  bind(formId: string, projectId: string): void {
    if (formId.length === 0 || projectId.length === 0) { throw new Error('Missing form or project ID') }
    let entries = this.read()
    entries[formId] = projectId
    this.write(entries)
  }

  unbind(formId: string): void {
    let entries = this.read()
    let kept: Record<string, string> = {}
    for (let id of Object.keys(entries)) { if (id !== formId) { kept[id] = entries[id] } }
    this.write(kept)
  }

  private write(entries: Record<string, string>): void {
    let temp = this.path + '.' + Date.now().toString() + '.' + Math.random().toString().substring(2) + '.tmp'
    let file = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
    try { fs.writeSync(file.fd, JSON.stringify(entries)) } finally { fs.closeSync(file) }
    try { fs.renameSync(temp, this.path) } finally {
      try { fs.unlinkSync(temp) } catch (_e) {}
    }
  }
}

export const formBindings: FormBindings = new FormBindings()
