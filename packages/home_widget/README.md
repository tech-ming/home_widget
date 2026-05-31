# home_widget（HarmonyOS 适配版）

[![Pub](https://img.shields.io/pub/v/home_widget.svg)](https://pub.dartlang.org/packages/home_widget)
[![likes](https://img.shields.io/pub/likes/home_widget)](https://pub.dev/packages/home_widget/score)
[![downloads](https://img.shields.io/pub/dm/home_widget)](https://pub.dev/packages/home_widget/score)
[![pub points](https://img.shields.io/pub/points/home_widget)](https://pub.dev/packages/home_widget/score)

基于 [home_widget](https://github.com/ABausG/home_widget) 的 HarmonyOS 适配分支。

## 简介

本包是 home_widget 的 fork 版本，在原版 Android / iOS 支持基础上新增了 HarmonyOS（OpenHarmony）平台支持，通过 `@kit.FormKit` 服务卡片 + `@kit.ArkData` 首选项实现与原版一致的数据通路与刷新能力。

home_widget 不会让你用 Flutter 直接绘制桌面卡片 —— 卡片 UI 仍需用原生代码编写（Android `RemoteViews` / iOS WidgetKit / HarmonyOS Form），插件负责跨平台统一的数据存储、卡片刷新、卡片启动检测等通用能力。

| iOS | Android |
| --- | --- |
| <img src="https://github.com/ABausG/home_widget/blob/main/.github/assets/demo_ios.png?raw=true" width="500px"> | <img src="https://github.com/ABausG/home_widget/blob/main/.github/assets/demo_android.png?raw=true" width="500px"> |

## 平台支持

| 能力 | Android | iOS | HarmonyOS |
| --- | :---: | :---: | :---: |
| `saveWidgetData` / `getWidgetData`（共享数据） | ✅ | ✅ | ✅ |
| `updateWidget`（触发卡片刷新） | ✅ | ✅ | ✅ |
| `setAppGroupId`（App Group / sandbox 共享） | ✅(no-op) | ✅ | ✅(no-op) |
| `initiallyLaunchedFromHomeWidget`（冷启动 URI） | ✅ | ✅ | ✅ |
| `widgetClicked`（前台点击事件流） | ✅ | ✅ | ✅ |
| `getInstalledWidgets`（已添加卡片列表） | ✅ | ✅ | ✅ |
| `saveFile` / `saveImage` / `renderFlutterWidget` | ✅ | ✅ | ✅ |
| `isRequestPinWidgetSupported` / `requestPinWidget` | ✅ | ❌ | ✅ (API 18+) |
| `registerBackgroundCallback`（卡片点击回 Dart） | ✅ | ✅ (iOS 17+) | ⚠️ 仅保存 handle |
| `initiallyLaunchedFromHomeWidgetConfigure` / `finishHomeWidgetConfigure` | ✅ | ❌ | ❌ |

## 安装

在项目 `pubspec.yaml` 中通过本地路径或仓库引用：

```yaml
dependencies:
  home_widget:
    path: packages/home_widget/packages/home_widget
```

```bash
flutter pub get
```

## 使用方法

跨平台 Dart API 与原版完全一致。下面给出常用调用，平台专属的接入细节请参考下文「HarmonyOS 说明」与上游文档。

### 保存数据

```dart
await HomeWidget.saveWidgetData<String>('title', '今日待办');
await HomeWidget.saveWidgetData<int>('counter', 5);
```

### 触发卡片刷新

```dart
await HomeWidget.updateWidget(
  name: 'CounterWidget',          // 跨平台通用名称
  androidName: 'CounterProvider',  // Android Widget Provider 类名
  iOSName: 'CounterWidget',        // iOS Widget kind
  ohosName: 'CounterCard',         // HarmonyOS 卡片名（与基类 getWidgetName 一致）
);
```

各平台名称解析顺序：

| 平台 | 名称优先级 |
| --- | --- |
| Android | `qualifiedAndroidName` > `androidName` > `name` |
| iOS | `iOSName` > `name` |
| HarmonyOS | `ohosName` > `name` |

### 检测卡片启动

```dart
// 冷启动：应用被卡片拉起时初始 URI
final initialUri = await HomeWidget.initiallyLaunchedFromHomeWidget();

// 热启动：应用在前台时收到的卡片点击事件
HomeWidget.widgetClicked.listen((uri) {
  // 处理 uri，例如路由跳转
});
```

### 应用内触发加桌

```dart
final supported = await HomeWidget.isRequestPinWidgetSupported() ?? false;
if (!supported) {
  // 老版本 launcher / 系统不支持，引导用户手动添加
  return;
}

await HomeWidget.requestPinWidget(
  // 跨平台通用名称（Android / iOS 也用）
  name: 'CounterWidget',
  // Android：WidgetProvider 全限定类名
  qualifiedAndroidName: 'com.example.app.widget.CounterProvider',
  // HarmonyOS：FormExtensionAbility 名（module.json5 中的 name）
  ohosAbilityName: 'CounterCard',
  // HarmonyOS：form_config.json 中声明的 form name
  ohosFormName: 'CounterCard',
  // HarmonyOS：可选，HAP 模块名，默认 'entry'
  ohosModuleName: 'entry',
  // HarmonyOS：可选，卡片初始尺寸枚举值，默认 2（即 2*2），其它值见 Form Kit 文档
  ohosDimension: 2,
);
```

平台行为差异：

| 平台 | 行为 |
| --- | --- |
| Android | API 26+ 部分 launcher 支持，弹「pin to home」对话框，用户确认后直接钉入 |
| HarmonyOS | API 18+ 通过 `formProvider.openFormManager` 拉起系统卡片管理页，用户再点「添加到桌面」完成加桌 |
| iOS | 不支持，调用为 no-op |

## HarmonyOS 说明

HarmonyOS 平台通过 ArkTS 服务卡片（Form）实现，需要在 OHOS 工程侧补充以下三步：声明 `FormExtensionAbility` → 继承基类 → 在卡片 UI 中按约定协议触发动作。

### 1. 在 module.json5 声明 FormExtensionAbility

在主工程 `entry/src/main/module.json5` 的 `extensionAbilities` 数组中为每个卡片声明一个条目，`srcEntry` 指向继承 `HomeWidgetFormExtensionAbility` 的 ETS 类：

```json5
{
  "module": {
    "extensionAbilities": [
      {
        "name": "CounterCard",
        "srcEntry": "./ets/widget/CounterCard.ets",
        "type": "form",
        "metadata": [
          {
            "name": "ohos.extension.form",
            "resource": "$profile:form_config"
          }
        ]
      }
    ]
  }
}
```

`$profile:form_config` 中按 HarmonyOS 标准声明卡片规格 / 默认尺寸 / 刷新周期等，参见[官方 Form 卡片文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/service-widget-overview-V5)。

### 2. 继承 HomeWidgetFormExtensionAbility

```typescript
import { HomeWidgetFormExtensionAbility } from '@ohos/home_widget';

export default class CounterCard extends HomeWidgetFormExtensionAbility {
  /// 与 Dart 端 HomeWidget.updateWidget(ohosName: 'CounterCard') 调用一致
  protected getWidgetName(): string {
    return 'CounterCard';
  }

  /// 可选：自定义下发给卡片 UI 的数据
  /// 默认行为：将 HomeWidgetPreferences 全量快照下发，卡片 UI 用 LocalStorageProp 消费
  // protected buildFormData(formId: string): Record<string, Object> {
  //   return { title: '自定义', count: 42 };
  // }
}
```

基类自动处理：

- `onAddForm` / `onRemoveForm` —— 维护 `widgetName ⇄ formId` 双向索引（preferences 中），供 `HomeWidget.updateWidget` 与 `HomeWidget.getInstalledWidgets` 使用。HarmonyOS 不提供枚举已添加卡片的公开 API，索引必须由插件自维护。
- `onUpdateForm` —— 在系统定时刷新时，自动从 preferences 读取最新数据并通过 `formProvider.updateForm` 推送给卡片。

如需完全自定义生命周期，可不继承基类，自行实现 `FormExtensionAbility` 并在 `onAddForm` / `onRemoveForm` 中手动调用 `HomeWidgetFormHelper.registerFormId` / `unregisterFormId`。

> ⚠️ **跨进程 preferences 缓存**：FormExtensionAbility 与 UIAbility 是不同进程，`@kit.ArkData` 的 preferences 在每个进程内独立缓存。如果重写 `onAddForm` / `buildFormData` 直接读 preferences（例如要消费 Dart 端刚写入的 pending 配置），**读取前必须先调用 `preferences.removePreferencesFromCacheSync` 丢弃 cache**，否则可能读到 FormExt 进程上一次启动时的陈旧数据。基类默认实现也存在此问题，自定义路径请自行处理。

### 3. 卡片 UI 消费数据

卡片 UI 通过 `LocalStorageProp` 读取插件下发的数据，key 即 `saveWidgetData` 时使用的 id：

```typescript
@Entry({ routeName: 'CounterCardEntry' })
@Component
struct CounterCard {
  @LocalStorageProp('title') title: string = '默认标题';
  @LocalStorageProp('counter') counter: number = 0;

  build() {
    Column() {
      Text(this.title)
      Text(`计数：${this.counter}`)
        .onClick(() => {
          // 见下一节：点击卡片拉起应用
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: { homeWidgetUri: 'myapp://counter/detail' },
          });
        })
    }
  }
}
```

### 4. 卡片点击拉起应用（URI 协议）

约定通过 `postCardAction` 的 `params.homeWidgetUri` 字段传递 URI 字符串：

```typescript
import { common } from '@kit.AbilityKit';

postCardAction(this, {
  action: 'router',           // 拉起 UIAbility（冷启动 + 热启动）
  abilityName: 'EntryAbility',
  params: {
    homeWidgetUri: 'myapp://detail/42',
  },
} as common.CardActionParam);
```

插件会从启动 / newWant 的 `want.parameters.homeWidgetUri` 提取 URI，通过 `HomeWidget.initiallyLaunchedFromHomeWidget()` 与 `HomeWidget.widgetClicked` 暴露给 Dart 端，行为与 Android / iOS 完全一致。

### 5. 能力对照表

| Dart API | HarmonyOS 实现 |
| --- | --- |
| `saveWidgetData` / `getWidgetData` | `@kit.ArkData` 首选项（`HomeWidgetPreferences`） |
| `updateWidget` | 按 widget 名查 formId 索引，逐个 `formProvider.updateForm` |
| `setAppGroupId` | 直接返回 `true`（OHOS 同 HAP 内 sandbox 天然共享） |
| `initiallyLaunchedFromHomeWidget` / `widgetClicked` | 读取 `want.parameters.homeWidgetUri` |
| `getInstalledWidgets` | 返回本地维护的索引，每项含 `ohosWidgetName` 与 `ohosFormId` |
| `saveFile` / `saveImage` / `renderFlutterWidget` | 写入 `getApplicationSupportDirectory()/home_widget/...`，卡片通过路径加载 |
| `isRequestPinWidgetSupported` | 直接返回 `true`（API version 18+ 必备） |
| `requestPinWidget` | 通过 `formProvider.openFormManager` 拉起系统卡片管理页，需传 `ohosAbilityName` + `ohosFormName` |
| `registerBackgroundCallback` | 仅保存 dispatcher / callback handle 到 preferences |

### 6. 已知限制

- **`requestPinWidget` 要求 API version 18+**：底层依赖 `formProvider.openFormManager`，低版本系统调用会抛错；通过 `isRequestPinWidgetSupported` 当前固定返回 `true`，更细的版本兜底请在应用层 try-catch 处理。另外该接口仅拉起系统卡片管理页，**最终是否加桌由用户在管理页确认**，不像 Android API 26+ 一步弹窗。
- **`registerBackgroundCallback` 未完整支持**：HarmonyOS 上从卡片直接触发后台 Dart 回调需要配合 Callee UIAbility 或 `onFormEvent` 在子进程中启动 FlutterEngine，本插件层只持久化 handle，完整链路由宿主应用按需自行集成。
- **跨进程 preferences 缓存**：见上一节注意事项，自定义 FormExtensionAbility 直接读 preferences 前需手动 evict cache。
- **数值类型精度**：OHOS `number` 不区分 `int` 与 `double`，Dart 端 `double 5.0` 经过往返可能被还原为 `int 5`。如需保留精度，请存为 `String`。
- **`getInstalledWidgets` 依赖索引**：列表来自 `onAddForm` 维护的索引，插件接入前已添加的卡片不会出现在列表中，需用户移除后重新添加。
- **`initiallyLaunchedFromHomeWidgetConfigure` / `finishHomeWidgetConfigure` 不支持**：HarmonyOS 卡片配置流程与 Android 的 widget configure Activity 不一致，相关方法在 OHOS 上固定返回 `null`。如果应用需要"添加前预配置"语义（Android configure activity 等价物），推荐用 App 内"先设置后加桌"流程：App 内写一份 pending 到 preferences → 调 `requestPinWidget` → 在自定义 `FormExtensionAbility.onAddForm` 中读 pending 写入 `{kind}.{formId}` 实例 key。

## Android 与 iOS 文档

Android / iOS 平台的详细接入步骤请参阅上游文档：

- 上游完整文档：<https://docs.page/ABausG/home_widget>
- Android：原生 `AppWidgetProvider` + `RemoteViews`
- iOS：WidgetKit + App Group 配置

## 上游仓库

- 原始仓库：[ABausG/home_widget](https://github.com/ABausG/home_widget)
- 原作者：[Anton Borries (@ABausG)](https://github.com/ABausG)

## 许可证

本项目遵循原始仓库的许可证（MIT License）。
