// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif

public class WebViewFlutterPlugin: NSObject, FlutterPlugin {
  /// Fix(kitar): 后台 scene 断开时默认不拆 registrar。
  ///
  /// UIKit 可以在进程仍处于后台、Flutter 引擎和 WKWebView 都还在树上时回调
  /// `sceneDidDisconnect`。这里拆掉 registrar 后，插件不会在 scene 重连时重建它，
  /// 迟到的 JSB / `evaluateJavaScript` 回包要么打到已销毁的 unowned（abort），
  /// 要么被 weak 早退丢掉，直播页回到前台也收不到消息。
  /// 真正结束插件生命周期的是 `detachFromEngine` 和 `applicationWillTerminate`。
  /// App 用 Remote Config `ios_webview_protection` 写入本开关；false 时恢复上游拆解。
  /// Crashlytics c1f6d36aeb7c105a32015504776adff5。
  public static var retainRegistrarOnSceneDisconnect = true

  /// Fix(kitar): scene 断开 / 应用终止 / 引擎 detach 之后，FlutterEngine 的 shell 随时会被
  /// `destroyContext` 置空。此时仍在树上的 WKWebView 被 PlatformViewsController 释放，pigeon
  /// finalizer 的 `removeStrongReference` 走 sendOnChannel 会命中引擎断言
  /// "Sending a message before the FlutterEngine has been run." 直接 abort
  /// （Organizer 样本 / flutter/flutter#168535）。置位期间 finalizer 直接跳过这条消息。
  /// 由 `sceneDidDisconnect` / `applicationWillTerminate` / `detachFromEngine` 置位，
  /// `sceneDidBecomeActive` 复位（scene 重连说明引擎仍在正常运行）。
  /// 注意：置位期间被释放的实例不会通知 Dart 移除强引用，Dart 侧 InstanceManager 会多留一个
  /// wrapper；进程终止场景无影响，后台断连重连场景为可接受的小泄漏。
  public static var isEngineTeardownImminent = false

  var proxyApiRegistrar: ProxyAPIRegistrar?

  init(binaryMessenger: FlutterBinaryMessenger) {
    proxyApiRegistrar = ProxyAPIRegistrar(
      binaryMessenger: binaryMessenger)
    proxyApiRegistrar?.setUp()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let binaryMessenger = registrar.messenger()
    #else
      let binaryMessenger = registrar.messenger
    #endif
    let plugin = WebViewFlutterPlugin(binaryMessenger: binaryMessenger)

    let viewFactory = FlutterViewFactory(instanceManager: plugin.proxyApiRegistrar!.instanceManager)

    #if os(iOS)
      registrar.addApplicationDelegate(plugin)
      registrar.addSceneDelegate(plugin)
    #endif

    registrar.register(viewFactory, withId: "plugins.flutter.io/webview")
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    tearDownProxyAPIRegistrar()
  }

  private func tearDownProxyAPIRegistrar() {
    // Fix(kitar): 先标记引擎即将不可用，再拆 registrar；拆掉后迟到的 finalizer 消息也会被跳过。
    WebViewFlutterPlugin.isEngineTeardownImminent = true
    proxyApiRegistrar?.ignoreCallsToDart = true
    proxyApiRegistrar?.tearDown()
    try? proxyApiRegistrar?.instanceManager.removeAllObjects()
    proxyApiRegistrar = nil
  }
}

#if os(iOS)
  extension WebViewFlutterPlugin: FlutterApplicationLifeCycleDelegate, FlutterSceneLifeCycleDelegate
  {
    public func applicationWillTerminate(_ application: UIApplication) {
      tearDownProxyAPIRegistrar()
    }

    public func sceneDidDisconnect(_: UIScene) {
      // Fix(kitar): scene 断开后引擎随时可能进入 destroyContext，无论是否保留 registrar
      // 都先标记 finalizer 保护；scene 重连时由 sceneDidBecomeActive 复位。
      WebViewFlutterPlugin.isEngineTeardownImminent = true
      // Fix(kitar): 见 retainRegistrarOnSceneDisconnect。保护开启时保留 registrar，
      // 让仍在树上的 WebView 继续收 JSB；关闭时走上游拆解，便于远程回滚。
      guard !WebViewFlutterPlugin.retainRegistrarOnSceneDisconnect else {
        return
      }
      tearDownProxyAPIRegistrar()
    }

    public func sceneDidBecomeActive(_: UIScene) {
      // Fix(kitar): scene 重连说明引擎仍在正常运行，恢复 finalizer 的 removeStrongReference。
      WebViewFlutterPlugin.isEngineTeardownImminent = false
    }
  }
#endif
