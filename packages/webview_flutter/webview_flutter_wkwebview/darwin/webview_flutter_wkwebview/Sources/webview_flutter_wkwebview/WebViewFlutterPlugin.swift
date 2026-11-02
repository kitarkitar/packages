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
      // Fix(kitar): 见 retainRegistrarOnSceneDisconnect。保护开启时保留 registrar，
      // 让仍在树上的 WebView 继续收 JSB；关闭时走上游拆解，便于远程回滚。
      guard !WebViewFlutterPlugin.retainRegistrarOnSceneDisconnect else {
        return
      }
      tearDownProxyAPIRegistrar()
    }
  }
#endif
