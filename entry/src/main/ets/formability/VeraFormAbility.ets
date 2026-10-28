import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility'
import formBindingData from '@ohos.app.form.formBindingData'
import formProvider from '@ohos.app.form.formProvider'
import Want from '@ohos.app.ability.Want'
import { store } from '../vera/ProjectStore'
import { buildFormBinding, refreshForms } from '../vera/FormUpdater'
import { formBindings } from '../vera/FormBindings'
import { liveBinding, liveFormTap } from '../vera/LiveFormService'

export default class VeraFormAbility extends FormExtensionAbility {
  private init(): void {
    store.init(this.context.filesDir)
    formBindings.init(this.context.filesDir)
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    this.init()
    let params = want.parameters as Record<string, Object>
    if (params !== null && params !== undefined && params['ohos.extra.param.key.form_name'] === 'live') {
      let id = params['ohos.extra.param.key.form_identity']
      let projectId = params['projectId']
      if (typeof id === 'string' && typeof projectId === 'string' && store.getProject(projectId) !== null) {
        formBindings.bind(id, projectId)
      }
      return liveBinding(typeof id === 'string' ? formBindings.projectFor(id) : '', typeof id === 'string' ? id : '')
    }
    return buildFormBinding()
  }

  async onUpdateForm(formId: string): Promise<void> {
    this.init()
    try {
      let info = await formProvider.getPublishedRunningFormInfoById(formId)
      await formProvider.updateForm(formId, info.formName === 'live' ?
        liveBinding(formBindings.projectFor(formId), formId) : buildFormBinding())
    } catch (e) { console.warn('VERA-FORM update: ' + (e as Error).message) }
  }

  onCastToNormalForm(formId: string): void { this.onUpdateForm(formId) }

  onRemoveForm(formId: string): void {
    this.init()
    formBindings.unbind(formId)
  }

  async onFormEvent(formId: string, message: string): Promise<void> {
    this.init()
    if (formBindings.projectFor(formId).length === 0) { return }
    try {
      await formProvider.updateForm(formId, liveFormTap(formId, message))
      await refreshForms(formId)
    } catch (e) { console.error('VERA-FORM event: ' + (e as Error).message) }
  }
}
