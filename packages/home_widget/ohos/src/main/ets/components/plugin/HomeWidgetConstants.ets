/**
 * HomeWidget 插件共享常量定义。
 *
 * 用于在主插件、Form 工具类、FormExtensionAbility 基类之间
 * 共享 preferences 名称、key 前缀、Channel 名称等常量，
 * 避免硬编码导致的不一致。
 */
export class HomeWidgetConstants {
  /// 存储用户数据的 preferences 文件名（对齐 Android 的 PREFERENCES 常量）
  static readonly PREFERENCES_NAME: string = 'HomeWidgetPreferences';

  /// 存储插件内部 metadata（formId 索引、回调 handle 等）的 preferences 文件名
  static readonly INTERNAL_PREFERENCES_NAME: string = 'HomeWidgetInternalPreferences';

  /// 正向索引前缀：`home_widget.form_ids.{widgetName}` → JSON 数组字符串
  /// 用于按 widgetName 查找所有已添加桌面的 formId
  static readonly FORM_IDS_PREFIX: string = 'home_widget.form_ids.';

  /// 反向索引前缀：`home_widget.form_name.{formId}` → widgetName
  /// 用于卡片移除时反查 widgetName 进行清理
  static readonly FORM_NAME_PREFIX: string = 'home_widget.form_name.';

  /// Dart 后台回调 dispatcher handle（顶层入口）保存 key
  static readonly CALLBACK_DISPATCHER_HANDLE_KEY: string = 'home_widget.callback_dispatcher';

  /// Dart 后台回调 callback handle（业务方法）保存 key
  static readonly CALLBACK_HANDLE_KEY: string = 'home_widget.callback_handle';

  /// 卡片拉起应用时通过 want.parameters 传递 URI 的约定 key。
  ///
  /// 卡片端在 `postCardAction({ action: 'router', params })` 中
  /// 通过该 key 传递目标 URI，应用端在启动 want 中提取，
  /// 用于实现与 Android/iOS 一致的「点击卡片携带 URI 启动应用」语义。
  static readonly LAUNCH_URI_PARAM_KEY: string = 'homeWidgetUri';

  /// 主方法通道名称（与 Android/iOS 一致）
  static readonly METHOD_CHANNEL_NAME: string = 'home_widget';

  /// 事件通道名称：应用前台时接收卡片点击事件
  static readonly EVENT_CHANNEL_NAME: string = 'home_widget/updates';

  /// 后台 Dart 回调通道名称
  static readonly BACKGROUND_CHANNEL_NAME: string = 'home_widget/background';
}
