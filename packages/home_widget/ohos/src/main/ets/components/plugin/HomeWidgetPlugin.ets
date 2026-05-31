import {
  AbilityAware,
  AbilityPluginBinding,
  EventChannel,
  EventSink,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  NewWantListener,
  StreamHandler,
} from '@ohos/flutter_ohos';
import { common, Want } from '@kit.AbilityKit';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { HomeWidgetConstants } from './HomeWidgetConstants';
import { HomeWidgetFormHelper } from './HomeWidgetFormHelper';

/**
 * HomeWidget 插件 OHOS 实现。
 *
 * 该插件提供与 Android / iOS 对齐的桌面卡片交互能力：
 * - `saveWidgetData` / `getWidgetData`：通过 `@kit.ArkData` 的 preferences 共享数据，
 *   UIAbility 与 FormExtensionAbility 共用同一 HAP sandbox，天然双向可见。
 * - `updateWidget`：根据 widget 名查 formId 索引，通过 `formProvider.updateForm` 逐个刷新。
 * - `initiallyLaunchedFromHomeWidget` + EventChannel：从 UIAbility 的 launchWant / newWant
 *   中提取卡片传入的 URI 参数（key 约定为 `homeWidgetUri`）。
 * - `getInstalledWidgets`：返回 `HomeWidgetFormHelper` 维护的索引快照。
 * - `requestPinWidget` / `isRequestPinWidgetSupported`：通过 `formProvider.openFormManager`
 *   拉起系统卡片管理页让用户加桌（API version 18+）。
 *
 * 关于 context 选择（重要！）：
 * preferences 文件位置由 context.preferencesDir 决定，UIAbilityContext 与
 * FormExtensionContext 都是 HAP 级（路径同为 `/data/storage/.../haps/{module}/preferences`），
 * 而 ApplicationContext 是 application 级（路径 `/data/storage/.../base/preferences`），二者不一致。
 * 由于卡片侧 FormExtensionAbility 只能取到 HAP 级 context，因此插件必须也使用 HAP 级 context
 * 写 prefs，否则会出现"主进程写入、卡片进程读不到"的跨进程隔离 bug。
 * 这里通过 `getActiveContext()` 统一获取：优先返回 UIAbility 的 context（HAP 级），
 * 仅当 Ability 尚未 attach 时回退到 ApplicationContext。
 *
 * 不支持 / 受限能力：
 * - `registerBackgroundCallback`：仅保存 handle 到 preferences；OHOS 上需配合 Callee UIAbility
 *   或 `onFormEvent` 在子进程中触发 Dart 回调，由开发者自行集成。
 */
export default class HomeWidgetPlugin
  implements FlutterPlugin, MethodCallHandler, AbilityAware, NewWantListener, StreamHandler {

  private channel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  /// onAttachedToEngine 时拿到的 ApplicationContext，作为 fallback 使用
  /// （仅当 Ability 尚未 attach 的极端时序下被回退到，正常路径不会走这里）
  private applicationContext: common.Context | null = null;
  private abilityBinding: AbilityPluginBinding | null = null;
  private eventSink: EventSink | null = null;

  /// 卡片冷启动携带的 URI，由 `initiallyLaunchedFromHomeWidget` 读取
  private launchUri: string | null = null;

  constructor() {
  }

  getUniqueClassName(): string {
    return 'HomeWidgetPlugin';
  }

  // ========== FlutterPlugin 生命周期 ==========

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.applicationContext = binding.getApplicationContext();

    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      HomeWidgetConstants.METHOD_CHANNEL_NAME,
    );
    this.channel.setMethodCallHandler(this);

    this.eventChannel = new EventChannel(
      binding.getBinaryMessenger(),
      HomeWidgetConstants.EVENT_CHANNEL_NAME,
    );
    this.eventChannel.setStreamHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    if (this.eventChannel !== null) {
      this.eventChannel.setStreamHandler(null);
      this.eventChannel = null;
    }
    this.applicationContext = null;
  }

  /// 统一获取当前有效的 context。
  ///
  /// 优先返回 UIAbility 的 context（HAP 级），与 FormExtensionContext 同沙箱，
  /// 保证 UIAbility 写入的 preferences 能被 FormExtensionAbility 读到。
  /// 仅当 onAttachedToAbility 尚未被调用时（理论上极少出现）回退到 ApplicationContext。
  private getActiveContext(): common.Context | null {
    if (this.abilityBinding !== null) {
      const ability = this.abilityBinding.getAbility();
      if (ability && ability.context) {
        return ability.context;
      }
    }
    return this.applicationContext;
  }

  // ========== AbilityAware 生命周期 ==========

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityBinding = binding;
    binding.addOnNewWantListener(this);

    // 冷启动场景：UIAbility 首次启动时通过 launchWant 携带卡片 URI
    const launchWant: Want | undefined = binding.getAbility().launchWant;
    const uri: string | null = HomeWidgetPlugin.extractWidgetUri(launchWant);
    if (uri !== null) {
      this.launchUri = uri;
    }
  }

  onDetachedFromAbility(): void {
    if (this.abilityBinding !== null) {
      this.abilityBinding.removeOnNewWantListener(this);
      this.abilityBinding = null;
    }
  }

  /// 应用已运行时被卡片再次拉起：热启动路径
  onNewWant(want: Want, _launchParams: AbilityConstant.LaunchParam): void {
    const uri: string | null = HomeWidgetPlugin.extractWidgetUri(want);
    if (uri !== null) {
      this.launchUri = uri;
      if (this.eventSink !== null) {
        this.eventSink.success(uri);
      }
    }
  }

  // ========== EventChannel StreamHandler ==========

  onListen(_args: ESObject, events: EventSink): void {
    this.eventSink = events;
  }

  onCancel(_args: ESObject): void {
    this.eventSink = null;
  }

  // ========== MethodChannel 调用分发 ==========

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'saveWidgetData':
        this.handleSaveWidgetData(call, result);
        break;
      case 'getWidgetData':
        this.handleGetWidgetData(call, result);
        break;
      case 'updateWidget':
        this.handleUpdateWidget(call, result);
        break;
      case 'setAppGroupId':
        // OHOS 同 HAP 内 sandbox 共享，不需要类似 iOS App Group 的设置
        result.success(true);
        break;
      case 'initiallyLaunchedFromHomeWidget':
        result.success(this.launchUri);
        break;
      case 'initiallyLaunchedFromHomeWidgetConfigure':
        // OHOS 卡片配置流程与 Android 不一致，没有对应的 configure Activity 概念
        result.success(null);
        break;
      case 'finishHomeWidgetConfigure':
        result.success(null);
        break;
      case 'isRequestPinWidgetSupported':
        this.handleIsRequestPinWidgetSupported(result);
        break;
      case 'requestPinWidget':
        this.handleRequestPinWidget(call, result);
        break;
      case 'getInstalledWidgets':
        this.handleGetInstalledWidgets(result);
        break;
      case 'registerBackgroundCallback':
        this.handleRegisterBackgroundCallback(call, result);
        break;
      default:
        result.notImplemented();
    }
  }

  // ========== 各 method 具体实现 ==========

  /// 写入数据到共享 preferences。
  /// 支持类型：boolean / number / string / Uint8Array / Array<number|string|boolean>。
  /// data 为 null 时删除对应 key。
  private handleSaveWidgetData(call: MethodCall, result: MethodResult): void {
    const ctx = this.getActiveContext();
    if (ctx === null) {
      result.error('-7', 'Context not initialized', null);
      return;
    }
    const id: string | null = call.argument('id') as string | null;
    if (id === null || id === undefined || id.length === 0) {
      result.error('-1', 'InvalidArguments saveWidgetData must be called with id', null);
      return;
    }
    const data: ESObject = call.argument('data') as ESObject;

    try {
      const prefs = preferences.getPreferencesSync(
        ctx,
        { name: HomeWidgetConstants.PREFERENCES_NAME },
      );
      if (data === null || data === undefined) {
        prefs.deleteSync(id);
      } else {
        prefs.putSync(id, data as preferences.ValueType);
      }
      prefs.flush()
        .then((): void => {
          result.success(true);
        })
        .catch((err: BusinessError): void => {
          result.error('-1', `Failed to save data: ${err.message}`, null);
        });
    } catch (err) {
      result.error('-1', `Failed to save data: ${(err as BusinessError).message}`, null);
    }
  }

  /// 读取共享 preferences 数据。
  /// 使用 `getAllSync` 拿到真实类型，避免 `getSync(key, defValue)` 必须传同类型默认值的限制。
  ///
  /// **跨进程缓存（重要）**：preferences 缓存是**每进程独立**的。卡片实例配置常由
  /// FormExtensionAbility 进程写入（如 `onAddForm` 迁移 pending），而本读取发生在
  /// UIAbility 进程。若不先丢弃缓存，UIAbility 进程会读到陈旧缓存（无对端刚写的 key），
  /// 表现为"卡片显示正确、App 内读到旧值/默认"。因此读取前必须
  /// `removePreferencesFromCacheSync` 强制从磁盘重载（与写入侧 FormExtensionAbility
  /// 的清缓存策略对齐）。
  private handleGetWidgetData(call: MethodCall, result: MethodResult): void {
    const ctx = this.getActiveContext();
    if (ctx === null) {
      result.error('-7', 'Context not initialized', null);
      return;
    }
    const id: string | null = call.argument('id') as string | null;
    if (id === null || id === undefined || id.length === 0) {
      result.error('-2', 'InvalidArguments getWidgetData must be called with id', null);
      return;
    }
    const defaultValue: ESObject = call.argument('defaultValue') as ESObject;

    try {
      // 强制丢弃本进程缓存，确保读到其他进程（FormExtensionAbility）刚写入的值
      preferences.removePreferencesFromCacheSync(
        ctx,
        { name: HomeWidgetConstants.PREFERENCES_NAME },
      );
      const prefs = preferences.getPreferencesSync(
        ctx,
        { name: HomeWidgetConstants.PREFERENCES_NAME },
      );
      if (!prefs.hasSync(id)) {
        result.success(defaultValue ?? null);
        return;
      }
      const all = prefs.getAllSync() as Record<string, Object>;
      const value: Object | undefined = all[id];
      result.success(value === undefined ? (defaultValue ?? null) : value);
    } catch (err) {
      result.error('-2', `Failed to get data: ${(err as BusinessError).message}`, null);
    }
  }

  /// 触发指定 widget 名下所有 formId 的卡片刷新。
  ///
  /// 命名优先级：`ohos` > `name`（`android` / `ios` 字段在 OHOS 上不使用）。
  /// formId 列表来自 `HomeWidgetFormHelper` 维护的索引。
  /// 卡片数据为 `HomeWidgetPreferences` 的全量快照，卡片 UI 可用 `LocalStorageProp(key)` 消费。
  private handleUpdateWidget(call: MethodCall, result: MethodResult): void {
    const ctx = this.getActiveContext();
    if (ctx === null) {
      result.error('-7', 'Context not initialized', null);
      return;
    }
    const ohosName: string | null = call.argument('ohos') as string | null;
    const fallbackName: string | null = call.argument('name') as string | null;
    const widgetName: string | null = (ohosName && ohosName.length > 0) ? ohosName : fallbackName;

    if (widgetName === null || widgetName === undefined || widgetName.length === 0) {
      result.error('-3', 'InvalidArguments updateWidget must be called with name or ohos', null);
      return;
    }

    try {
      const formIds: string[] = HomeWidgetFormHelper.getFormIds(ctx, widgetName);
      if (formIds.length === 0) {
        // 桌面无该卡片实例时视为成功，与 Android 的「广播无消费者」行为对齐
        result.success(true);
        return;
      }

      const prefs = preferences.getPreferencesSync(
        ctx,
        { name: HomeWidgetConstants.PREFERENCES_NAME },
      );
      const allData = prefs.getAllSync() as Record<string, Object>;
      const binding = formBindingData.createFormBindingData(allData);

      // 逐个 formId 推送刷新，单个失败不阻塞其他
      const updates: Array<Promise<void>> = formIds.map((formId: string): Promise<void> => {
        return formProvider.updateForm(formId, binding).catch((err: BusinessError): void => {
          console.warn(`[HomeWidget] updateForm(${formId}) failed: ${err.message}`);
        });
      });
      Promise.all(updates)
        .then((): void => {
          result.success(true);
        })
        .catch((err: BusinessError): void => {
          result.error('-3', `Failed to update widgets: ${err.message}`, null);
        });
    } catch (err) {
      result.error('-3', `Failed to update widgets: ${(err as BusinessError).message}`, null);
    }
  }

  /// 列出已添加到桌面的所有卡片实例（widgetName + formId）。
  private handleGetInstalledWidgets(result: MethodResult): void {
    const ctx = this.getActiveContext();
    if (ctx === null) {
      result.error('-7', 'Context not initialized', null);
      return;
    }
    try {
      const forms: Array<Record<string, string>> = HomeWidgetFormHelper.getAllInstalledForms(ctx);
      result.success(forms);
    } catch (err) {
      result.error('-5', `Failed to get installed widgets: ${(err as BusinessError).message}`, null);
    }
  }

  /// 保存 Dart 后台回调 handle 到内部 preferences。
  ///
  /// OHOS 上无法像 Android 那样在 BroadcastReceiver 中拉起 headless Dart engine，
  /// 也不像 iOS 17 提供 AppIntent + Dart 调度。
  /// 此处仅持久化 handle，开发者可在 Callee UIAbility / `onFormEvent` 内
  /// 自行启动 FlutterEngine 并通过 `home_widget/background` channel 触发回调。
  private handleRegisterBackgroundCallback(call: MethodCall, result: MethodResult): void {
    const ctx = this.getActiveContext();
    if (ctx === null) {
      result.error('-7', 'Context not initialized', null);
      return;
    }
    try {
      // Dart 端传入的是 [dispatcherHandle, callbackHandle] 数组
      const args: ESObject = call.args;
      if (!args || !Array.isArray(args) || (args as Array<Object>).length < 2) {
        result.error(
          '-6',
          'InvalidArguments registerBackgroundCallback expects [dispatcher, callback]',
          null,
        );
        return;
      }
      const arr = args as Array<number>;
      const dispatcher: number = arr[0];
      const callback: number = arr[1];

      const prefs = preferences.getPreferencesSync(
        ctx,
        { name: HomeWidgetConstants.INTERNAL_PREFERENCES_NAME },
      );
      prefs.putSync(HomeWidgetConstants.CALLBACK_DISPATCHER_HANDLE_KEY, dispatcher);
      prefs.putSync(HomeWidgetConstants.CALLBACK_HANDLE_KEY, callback);
      prefs.flush()
        .then((): void => {
          result.success(true);
        })
        .catch((err: BusinessError): void => {
          result.error('-6', `Failed to register callback: ${err.message}`, null);
        });
    } catch (err) {
      result.error('-6', `Failed to register callback: ${(err as BusinessError).message}`, null);
    }
  }

  /// 检查当前系统是否支持「应用内拉起加桌」。
  ///
  /// `formProvider.openFormManager` 从 API version 18 开始提供（HarmonyOS NEXT 5.0+）。
  /// 由于 ArkTS 严格模式不便做动态 API 探测，这里直接返回 true，
  /// 实际调用 `requestPinWidget` 时若运行时不支持会在 catch 中下发错误。
  private handleIsRequestPinWidgetSupported(result: MethodResult): void {
    result.success(true);
  }

  /// 拉起系统卡片管理页让用户把指定卡片添加到桌面。
  ///
  /// OHOS 等价的 Android `requestPinAppWidget` 是 `formProvider.openFormManager(want)`，
  /// 二者在「用户主动加桌」这个语义上是对齐的，但 OHOS 必然要进系统卡片管理页二次确认，
  /// 而 Android API 26+ 直接弹「pin to home」对话框。
  ///
  /// Dart 端通过 method arguments 传入：
  /// - `ohosAbilityName`：卡片对应的 FormExtensionAbility 名（必填）
  /// - `ohosFormName`：form_config.json 中声明的 form name（必填）
  /// - `ohosModuleName`：HAP 模块名（可选，缺省取 `entry`）
  /// - `ohosDimension`：卡片初始尺寸枚举值（可选，缺省取 2，即 2*2）
  private handleRequestPinWidget(call: MethodCall, result: MethodResult): void {
    const ctx = this.getActiveContext();
    if (ctx === null) {
      result.error('-7', 'Context not initialized', null);
      return;
    }

    const abilityName: string | null = call.argument('ohosAbilityName') as string | null;
    const formName: string | null = call.argument('ohosFormName') as string | null;
    if (!abilityName || abilityName.length === 0 || !formName || formName.length === 0) {
      result.error(
        '-8',
        'InvalidArguments requestPinWidget on OHOS requires ohosAbilityName and ohosFormName',
        null,
      );
      return;
    }
    const moduleNameArg: string | null = call.argument('ohosModuleName') as string | null;
    const moduleName: string = (moduleNameArg && moduleNameArg.length > 0) ? moduleNameArg : 'entry';
    const dimensionArg: number | null = call.argument('ohosDimension') as number | null;
    const dimension: number = (dimensionArg !== null && dimensionArg !== undefined) ? dimensionArg : 2;

    try {
      // applicationInfo.name 即为当前应用的 bundleName
      const bundleName: string = ctx.applicationInfo.name;
      const params: Record<string, Object> = {
        'ohos.extra.param.key.form_dimension': dimension,
        'ohos.extra.param.key.form_name': formName,
        'ohos.extra.param.key.module_name': moduleName,
      };
      const want: Want = {
        bundleName: bundleName,
        abilityName: abilityName,
        parameters: params,
      };
      formProvider.openFormManager(want);
      // openFormManager 是同步触发的（拉起系统页面，不返回 Promise），调用成功即 resolve
      result.success(null);
    } catch (err) {
      const bizErr = err as BusinessError;
      result.error(
        '-8',
        `Failed to open form manager: code=${bizErr.code}, message=${bizErr.message}`,
        null,
      );
    }
  }

  /// 从 Want 的 parameters 中提取卡片传入的 URI。
  private static extractWidgetUri(want: Want | undefined): string | null {
    if (!want || !want.parameters) {
      return null;
    }
    const raw: Object | undefined = want.parameters[HomeWidgetConstants.LAUNCH_URI_PARAM_KEY];
    if (raw === undefined || raw === null) {
      return null;
    }
    const str: string = String(raw);
    return str.length > 0 ? str : null;
  }
}
