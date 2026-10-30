import { store, Project } from '../vera/ProjectStore'
import { formBindings } from '../vera/FormBindings'
import { refreshForms } from '../vera/FormUpdater'
import formProvider from '@ohos.app.form.formProvider'

@Entry
@Component
struct WidgetBindPage {
  @State projects: Project[] = []
  @State error: string = ''
  private formId: string = ''

  aboutToAppear(): void {
    let params = this.getUIContext().getRouter().getParams() as Record<string, string>
    this.formId = params['formId'] || ''
    this.projects = store.listProjects()
  }

  private async bind(project: Project): Promise<void> {
    try {
      // Do not accept arbitrary form IDs supplied as launch parameters.
      let info = await formProvider.getPublishedRunningFormInfoById(this.formId)
      if (info.formName !== 'live' || info.bundleName !== 'com.vera.probe.dyn') { throw new Error('Not a VERA live widget') }
      formBindings.bind(this.formId, project.id)
      await refreshForms()
      this.getUIContext().getRouter().back()
    } catch (e) { this.error = (e as Error).message }
  }

  build() {
    Navigation() {
      Column({ space: 12 }) {
        Text('Choose the app for this home-screen widget.').fontSize(15).fontColor('#64748B').padding(16)
        if (this.error.length > 0) { Text(this.error).fontColor('#B91C1C').padding(12) }
        List({ space: 10 }) {
          ForEach(this.projects, (project: Project) => {
            ListItem() {
              Button(project.icon + '  ' + project.name).type(ButtonType.Normal)
                .width('100%').height(56).borderRadius(12).backgroundColor('#FFFFFF').fontColor('#172033')
                .onClick(() => { this.bind(project) })
            }
          }, (project: Project) => project.id)
        }.width('100%').padding(16).layoutWeight(1)
      }.width('100%').height('100%').backgroundColor('#F8FAFC')
    }.title('Choose widget app').titleMode(NavigationTitleMode.Mini)
  }
}
