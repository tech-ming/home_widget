import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { HomeWidgetConstants } from './HomeWidgetConstants';

/**
 * formId 索引管理工具。
 *
 * OHOS 没有像 Android `AppWidgetManager.getAppWidgetIds()` 那样的公开 API
 * 用于枚举本应用已添加到桌面的所有卡片实例，
 * 因此需要在 `FormExtensionAbility.onAddForm` / `onRemoveForm` 中
 * 手动维护 `widgetName ⇄ formId` 的双向索引。
 *
 * 该索引被 home_widget 的 `updateWidget` 与 `getInstalledWidgets` 复用。
 *
 * 用法：
 * - 自定义 FormExtensionAbility 在 onAddForm 调用 `registerFormId`
 * - 在 onRemoveForm 调用 `unregisterFormId`
 *
 * 或直接继承 `HomeWidgetFormExtensionAbility` 由基类自动维护。
 */
export class HomeWidgetFormHelper {
  /**
   * 在 formId 索引中登记一个卡片实例。
   *
   * 应当在 `FormExtensionAbility.onAddForm` 内调用。
   *
   * @param context FormExtensionAbility 的上下文，用于获取 preferences
   * @param widgetName 卡片名称，必须与 Dart 端 `updateWidget(name: ...)` 传入的名称一致
   * @param formId 当前卡片实例的 formId（从 onAddForm 的 want.parameters 取得）
   */
  static registerFormId(context: common.Context, widgetName: string, formId: string): void {
    if (!formId || !widgetName) {
      return;
    }
    const prefs = preferences.getPreferencesSync(
      context,
      { name: HomeWidgetConstants.INTERNAL_PREFERENCES_NAME },
    );

    // 正向索引：widgetName → [formId1, formId2, ...]
    const idsKey: string = `${HomeWidgetConstants.FORM_IDS_PREFIX}${widgetName}`;
    const ids: string[] = HomeWidgetFormHelper.readIdArray(prefs, idsKey);
    if (!ids.includes(formId)) {
      ids.push(formId);
      prefs.putSync(idsKey, JSON.stringify(ids));
    }

    // 反向索引：formId → widgetName（用于 onRemoveForm 反查）
    const nameKey: string = `${HomeWidgetConstants.FORM_NAME_PREFIX}${formId}`;
    prefs.putSync(nameKey, widgetName);

    prefs.flush();
  }

  /**
   * 从 formId 索引中移除一个卡片实例。
   *
   * 应当在 `FormExtensionAbility.onRemoveForm` 内调用。
   */
  static unregisterFormId(context: common.Context, formId: string): void {
    if (!formId) {
      return;
    }
    const prefs = preferences.getPreferencesSync(
      context,
      { name: HomeWidgetConstants.INTERNAL_PREFERENCES_NAME },
    );

    const nameKey: string = `${HomeWidgetConstants.FORM_NAME_PREFIX}${formId}`;
    if (!prefs.hasSync(nameKey)) {
      return;
    }
    const widgetName: string = prefs.getSync(nameKey, '') as string;

    // 从正向索引中剔除该 formId
    if (widgetName) {
      const idsKey: string = `${HomeWidgetConstants.FORM_IDS_PREFIX}${widgetName}`;
      const ids: string[] = HomeWidgetFormHelper.readIdArray(prefs, idsKey);
      const filtered: string[] = ids.filter((id: string): boolean => id !== formId);
      if (filtered.length === 0) {
        prefs.deleteSync(idsKey);
      } else {
        prefs.putSync(idsKey, JSON.stringify(filtered));
      }
    }

    prefs.deleteSync(nameKey);
    prefs.flush();
  }

  /**
   * 查询某个 widgetName 当前所有已添加到桌面的 formId。
   *
   * 由 `HomeWidgetPlugin.updateWidget` 调用。
   */
  static getFormIds(context: common.Context, widgetName: string): string[] {
    const prefs = preferences.getPreferencesSync(
      context,
      { name: HomeWidgetConstants.INTERNAL_PREFERENCES_NAME },
    );
    const idsKey: string = `${HomeWidgetConstants.FORM_IDS_PREFIX}${widgetName}`;
    return HomeWidgetFormHelper.readIdArray(prefs, idsKey);
  }

  /**
   * 枚举所有已添加到桌面的卡片实例。
   *
   * 返回每个实例对应的 widgetName 与 formId，
   * 由 `HomeWidgetPlugin.getInstalledWidgets` 调用。
   */
  static getAllInstalledForms(context: common.Context): Array<Record<string, string>> {
    const prefs = preferences.getPreferencesSync(
      context,
      { name: HomeWidgetConstants.INTERNAL_PREFERENCES_NAME },
    );
    const all = prefs.getAllSync() as Record<string, Object>;
    const result: Array<Record<string, string>> = [];
    // 通过反向索引枚举：home_widget.form_name.{formId} → widgetName
    Object.keys(all).forEach((key: string): void => {
      if (key.startsWith(HomeWidgetConstants.FORM_NAME_PREFIX)) {
        const formId: string = key.substring(HomeWidgetConstants.FORM_NAME_PREFIX.length);
        const widgetName: string = String(all[key]);
        const entry: Record<string, string> = {
          'ohosFormId': formId,
          'ohosWidgetName': widgetName,
        };
        result.push(entry);
      }
    });
    return result;
  }

  /**
   * 从 preferences 读取 JSON 字符串并解析为字符串数组。
   *
   * 解析失败时返回空数组，避免索引污染导致后续操作崩溃。
   */
  private static readIdArray(prefs: preferences.Preferences, key: string): string[] {
    if (!prefs.hasSync(key)) {
      return [];
    }
    const raw: string = prefs.getSync(key, '[]') as string;
    try {
      const parsed = JSON.parse(raw) as Object;
      if (Array.isArray(parsed)) {
        return (parsed as Array<Object>).map((item: Object): string => String(item));
      }
      return [];
    } catch (_err) {
      // HACK: JSON 损坏时清空索引，避免无限重试。生产环境应记录日志。
      return [];
    }
  }
}
