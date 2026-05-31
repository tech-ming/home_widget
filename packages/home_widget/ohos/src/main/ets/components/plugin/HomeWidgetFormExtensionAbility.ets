import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { HomeWidgetConstants } from './HomeWidgetConstants';
import { HomeWidgetFormHelper } from './HomeWidgetFormHelper';

/**
 * HomeWidget 提供的 FormExtensionAbility 基类。
 *
 * 开发者继承本类即可获得：
 * - 卡片添加 / 移除时自动维护 formId 索引（供 Dart 端 `updateWidget`、`getInstalledWidgets` 使用）
 * - 卡片刷新时自动从共享 preferences 读取数据并下发到卡片 UI
 *
 * 用法示例：
 * ```ets
 * import { HomeWidgetFormExtensionAbility } from '@ohos/home_widget';
 *
 * export default class MyCounterCard extends HomeWidgetFormExtensionAbility {
 *   // 卡片名称必须与 Dart 端 HomeWidget.updateWidget(name: 'MyCounterCard') 一致
 *   protected getWidgetName(): string {
 *     return 'MyCounterCard';
 *   }
 * }
 * ```
 *
 * 如需自定义数据组装逻辑，重写 `buildFormData(formId)` 即可：
 * ```ets
 * protected buildFormData(formId: string): Record<string, Object> {
 *   return { title: '自定义标题', count: 42 };
 * }
 * ```
 */
export abstract class HomeWidgetFormExtensionAbility extends FormExtensionAbility {

  /**
   * 卡片名称，必须与 Dart 端 `HomeWidget.updateWidget(name: 'xxx')` 调用使用的名称一致。
   *
   * 默认返回空字符串，此时基类会回退到 `onAddForm` 收到的 Want 参数
   * `ohos.extra.param.key.form_name`（即 module.json5 中声明的 form name）。
   *
   * 当 Dart 端使用的 widget name 与 module.json5 中的 form name 不一致时，
   * 子类应重写此方法显式返回 Dart 端使用的名字，以保证索引正确。
   */
  protected getWidgetName(): string {
    return '';
  }

  /**
   * 组装下发给卡片 UI 的数据。
   *
   * 默认行为：将 `HomeWidgetPreferences` 中的全部键值打包下发。
   * 卡片 UI 可通过 `LocalStorageProp('key')` 直接消费。
   *
   * 重写时可返回任意可被 `formBindingData.createFormBindingData` 接受的对象。
   */
  protected buildFormData(_formId: string): Record<string, Object> {
    try {
      const prefs = preferences.getPreferencesSync(
        this.context,
        { name: HomeWidgetConstants.PREFERENCES_NAME },
      );
      // getAllSync 返回 Record<string, ValueType>，其中 ValueType 兼容 Object
      return prefs.getAllSync() as Record<string, Object>;
    } catch (err) {
      console.warn(`[HomeWidget] buildFormData 读取 preferences 失败: ${(err as BusinessError).message}`);
      return {};
    }
  }

  /**
   * 卡片被添加到桌面时回调。
   *
   * 基类会自动登记 formId 索引，子类如需在添加时执行额外逻辑可重写
   * 但务必调用 `super.onAddForm(want)` 或手动调用 `HomeWidgetFormHelper.registerFormId`。
   */
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId: string = HomeWidgetFormExtensionAbility.extractStringParam(
      want, formInfo.FormParam.IDENTITY_KEY,
    );
    // 优先使用子类显式声明的 widgetName（与 Dart 端 updateWidget 调用一致）；
    // 子类未声明时回退到 want.parameters 中的 form name。
    const customName: string = this.getWidgetName();
    const wantName: string = HomeWidgetFormExtensionAbility.extractStringParam(
      want, formInfo.FormParam.NAME_KEY,
    );
    const widgetName: string = customName.length > 0 ? customName : wantName;

    if (formId.length > 0 && widgetName.length > 0) {
      HomeWidgetFormHelper.registerFormId(this.context, widgetName, formId);
    }
    return formBindingData.createFormBindingData(this.buildFormData(formId));
  }

  /**
   * 卡片被移除时回调。
   *
   * 基类会自动清理 formId 索引。
   */
  onRemoveForm(formId: string): void {
    HomeWidgetFormHelper.unregisterFormId(this.context, formId);
  }

  /**
   * 卡片刷新时回调（系统定时触发或卡片内部 postCardAction 触发）。
   *
   * 基类会调用 `buildFormData` 并通过 `formProvider.updateForm` 下发到 UI。
   */
  onUpdateForm(formId: string): void {
    const data = formBindingData.createFormBindingData(this.buildFormData(formId));
    formProvider.updateForm(formId, data).catch((err: BusinessError): void => {
      console.warn(`[HomeWidget] onUpdateForm 调用 updateForm 失败: ${err.message}`);
    });
  }

  /**
   * 从 want.parameters 中安全地提取字符串参数。
   *
   * Want.parameters 是 Record<string, Object>，不能直接当字符串用。
   */
  private static extractStringParam(want: Want, key: string): string {
    const params: Record<string, Object> | undefined = want.parameters;
    if (!params) {
      return '';
    }
    const value: Object | undefined = params[key];
    if (value === undefined || value === null) {
      return '';
    }
    return String(value);
  }
}
