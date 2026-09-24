import UIAbility from '@ohos.app.ability.UIAbility'
import Want from '@ohos.app.ability.Want'
import AbilityConstant from '@ohos.app.ability.AbilityConstant'
import window from '@ohos.window'
import hilog from '@ohos.hilog'
import router from '@ohos.router'
import { refreshForms } from '../vera/FormUpdater'
import { settings } from '../vera/SettingsStore'
import { requestCalendarPermissions } from '../vera/VeraCalendar'
import { runProbe } from '../vera/IntentProbe'
import { loadCatalogFile } from '../vera/VeraCatalogFile'

const DOMAIN = 0x0000

class ProjectNavParams {
  projectId: string = ''
}

export default class EntryAbility extends UIAbility {
  private pendingProjectId: string = ''

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'VERA', 'EntryAbility onCreate')
    // Before anything can be generated or compiled: the vocabulary a program is
    // allowed to use must not change underneath a program that is being written.
    loadCatalogFile(this.context.filesDir)
    this.extractApiKey(want)
    this.extractSelectorKey(want)
    this.extractServerUrl(want)
    this.extractProjectId(want)
    this.extractProbe(want)
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'VERA', 'EntryAbility onNewWant')
    this.extractApiKey(want)
    this.extractSelectorKey(want)
    this.extractServerUrl(want)
    this.extractProjectId(want)
    this.extractProbe(want)
    if (this.pendingProjectId.length > 0) {
      this.navigateToProject()
    }
  }

  /**
   * Accepts the DeepSeek key as a launch parameter, so it never has to be typed
   * on the phone:
   *
   *   hdc shell aa start -a EntryAbility -b com.vera.probe.dyn \
   *     --ps deepseekKey sk-...
   *
   * The key itself is never logged -- only the fact that one arrived.
   */
  private extractApiKey(want: Want): void {
    if (want.parameters === null || want.parameters === undefined) { return }
    let params = want.parameters as Record<string, Object>
    let key = params['deepseekKey']
    if (key === null || key === undefined || typeof key !== 'string') { return }
    let text = (key as string).trim()
    if (text.length === 0) { return }
    settings.init(this.context.filesDir)
    settings.setApiKey(text)
    hilog.info(DOMAIN, 'VERA', 'DeepSeek API key updated from launch parameter')
  }

  /**
   * The TypeSafe key for the intent selection step, given the same way:
   *     --ps typesafeKey ...
   *
   * Optional: without it every intent in the catalogue goes into the prompt.
   */
  private extractSelectorKey(want: Want): void {
    if (want.parameters === null || want.parameters === undefined) { return }
    let params = want.parameters as Record<string, Object>
    let key = params['typesafeKey']
    if (key === null || key === undefined || typeof key !== 'string') { return }
    let text = (key as string).trim()
    if (text.length === 0) { return }
    settings.init(this.context.filesDir)
    settings.setSelectorKey(text)
    hilog.info(DOMAIN, 'VERA', 'TypeSafe key updated from launch parameter')
  }

  /**
   * Where vera-server lives, given the same way as the key:
   *     --ps veraServer http://host:port
   */
  private extractServerUrl(want: Want): void {
    if (want.parameters === null || want.parameters === undefined) { return }
    let params = want.parameters as Record<string, Object>
    let url = params['veraServer']
    if (url === null || url === undefined || typeof url !== 'string') { return }
    let text = (url as string).trim()
    if (text.length === 0) { return }
    settings.init(this.context.filesDir)
    settings.setServerUrl(text)
    hilog.info(DOMAIN, 'VERA', 'vera-server address updated from launch parameter')
  }

  /**
   * Development only: calls one intent named on the command line, so a
   * candidate row can be tried before it is written into the catalogue. See
   * IntentProbe.ets for what it takes and why it lives here.
   *
   * Reachable only from a launch parameter, so only from a shell on the device.
   */
  private extractProbe(want: Want): void {
    if (want.parameters === null || want.parameters === undefined) { return }
    let params = want.parameters as Record<string, Object>
    let target = params['probeTarget']
    if (target === null || target === undefined || typeof target !== 'string') { return }
    let payload = params['probeParams']
    let mode = params['probeMode']
    runProbe((target as string).trim(),
      payload !== null && payload !== undefined && typeof payload === 'string' ? (payload as string) : '',
      mode !== null && mode !== undefined && typeof mode === 'string' ? (mode as string) : 'background')
  }

  private extractProjectId(want: Want): void {
    if (want.parameters !== null && want.parameters !== undefined) {
      let params = want.parameters as Record<string, Object>
      let id = params['projectId']
      if (id !== null && id !== undefined && typeof id === 'string') {
        this.pendingProjectId = id as string
        hilog.info(DOMAIN, 'VERA', 'Launch with projectId: ' + this.pendingProjectId)
      }
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'VERA', 'EntryAbility onWindowStageCreate')
    // std/calendar needs READ_CALENDAR and WRITE_CALENDAR, which are user_grant
    // and so cannot come from the signature. Asked here rather than at the
    // first calendar call, because a permission dialog appearing in the middle
    // of a generated program's handler gives no clue what asked for it.
    requestCalendarPermissions(this.context)
    windowStage.loadContent('pages/Index', (err): void => {
      if (err?.code) {
        hilog.error(DOMAIN, 'VERA', 'loadContent failed')
        return
      }
      hilog.info(DOMAIN, 'VERA', 'loadContent ok')
      if (this.pendingProjectId.length > 0) {
        setTimeout(() => { this.navigateToProject() }, 100)
      }
    })
  }

  private navigateToProject(): void {
    if (this.pendingProjectId.length === 0) { return }
    let projectId = this.pendingProjectId
    this.pendingProjectId = ''
    try {
      let p = new ProjectNavParams()
      p.projectId = projectId
      router.pushUrl({ url: 'pages/ProjectPage', params: p })
    } catch (e) {
      hilog.error(DOMAIN, 'VERA', 'Navigate to project failed: ' + (e as Error).message)
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'VERA', 'EntryAbility onDestroy')
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'VERA', 'EntryAbility onWindowStageDestroy')
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'VERA', 'EntryAbility onForeground')
    refreshForms()
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'VERA', 'EntryAbility onBackground')
  }
}
