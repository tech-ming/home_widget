// HomeWidget HarmonyOS 插件入口
//
// - 默认导出 HomeWidgetPlugin：供 Flutter 生成的 GeneratedPluginRegistrant 自动注册
// - 命名导出 HomeWidgetFormExtensionAbility：开发者继承用于构建桌面卡片
// - 命名导出 HomeWidgetFormHelper：手写 FormExtensionAbility 时直接维护 formId 索引
// - 命名导出 HomeWidgetConstants：跨模块共享的 preferences 文件名 / want 参数 key 等常量

import HomeWidgetPlugin from './src/main/ets/components/plugin/HomeWidgetPlugin';
import { HomeWidgetFormExtensionAbility } from './src/main/ets/components/plugin/HomeWidgetFormExtensionAbility';
import { HomeWidgetFormHelper } from './src/main/ets/components/plugin/HomeWidgetFormHelper';
import { HomeWidgetConstants } from './src/main/ets/components/plugin/HomeWidgetConstants';

export default HomeWidgetPlugin;
export { HomeWidgetPlugin, HomeWidgetFormExtensionAbility, HomeWidgetFormHelper, HomeWidgetConstants };
