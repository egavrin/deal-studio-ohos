import formBindingData from '@ohos.app.form.formBindingData'
import { store } from './ProjectStore'
import { formBindings } from './FormBindings'
import { LiveFrame, WidgetSession } from './VeraLiveWidget'
import { veraStateStamp } from './VeraStateStamp'

export function liveFrame(projectId: string): LiveFrame {
  let fallback = new LiveFrame()
  fallback.projectId = projectId
  if (projectId.length === 0) { fallback.status = 'Tap the title to choose an app'; return fallback }
  let project = store.getProject(projectId)
  if (project === null) {
    fallback.title = 'App removed'
    fallback.projectId = ''
    return fallback
  }
  fallback.title = project.name
  fallback.icon = project.icon
  let version = store.getLatestVersion(projectId)
  if (version === null || version.vbc2.length === 0) { fallback.status = 'Open project'; return fallback }
  try {
    let saved = store.loadState(projectId, version.id, veraStateStamp(version.vbc2))
    let session = new WidgetSession(version.vbc2, version.id, saved)
    let frame = session.frame(projectId, project.name, project.icon)
    // A clock-dependent init must not generate a different state/token on the first tap.
    if (frame.live && saved.length === 0) {
      store.saveState(projectId, version.id, veraStateStamp(version.vbc2), session.encodedState())
    }
    return frame
  } catch (e) {
    fallback.status = (e as Error).message
    console.error('VERA-FORM render: ' + fallback.status)
    return fallback
  }
}

export function liveBinding(projectId: string, formId: string = ''): formBindingData.FormBindingData {
  let frame = liveFrame(projectId)
  frame.formId = formId
  return formBindingData.createFormBindingData(frame)
}

/** Render, validate event, dispatch, re-render, THEN commit. Failed/effectful taps never save. */
export function liveFormTap(formId: string, message: string): formBindingData.FormBindingData {
  let start = Date.now()
  let projectId = formBindings.projectFor(formId)
  let project = store.getProject(projectId)
  let version = store.getLatestVersion(projectId)
  if (project === null || version === null || version.vbc2.length === 0) { return liveBinding(projectId) }
  let saved = store.loadState(projectId, version.id, veraStateStamp(version.vbc2))
  try {
    let params = JSON.parse(message) as Record<string, Object>
    if (typeof params['token'] !== 'string' || typeof params['handler'] !== 'string' || typeof params['value'] !== 'number') {
      throw new Error('Invalid widget event')
    }
    console.info('VERA-FORM event action=' + String(params['handler']) + ' value=' + String(params['value']))
    let session = new WidgetSession(version.vbc2, version.id, saved)
    session.tap(session.frame(projectId, project.name, project.icon), params['token'] as string,
      params['handler'] as string, params['value'] as number)
    let frame = session.frame(projectId, project.name, project.icon)
    frame.formId = formId
    store.saveState(projectId, version.id, veraStateStamp(version.vbc2), session.encodedState())
    console.info('VERA-FORM tap ms=' + (Date.now() - start).toString() + ' bytes=' + JSON.stringify(frame).length.toString())
    return formBindingData.createFormBindingData(frame)
  } catch (e) {
    let frame = liveFrame(projectId)
    frame.formId = formId
    frame.status = (e as Error).message
    console.warn('VERA-FORM tap rejected: ' + frame.status)
    return formBindingData.createFormBindingData(frame)
  }
}
