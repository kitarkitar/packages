// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import XCTest

@testable import webview_flutter_wkwebview

#if os(iOS)
  import Flutter
  import UIKit
#endif

class WebViewFlutterPluginTests: XCTestCase {
  #if os(iOS)
    func testInstanceManagerIsDeallocatedInApplicationWillTerminate() {
      let plugin = WebViewFlutterPlugin(binaryMessenger: TestBinaryMessenger())
      plugin.proxyApiRegistrar!.setUp()

      let view = UIView()
      _ = plugin.proxyApiRegistrar!.instanceManager.addHostCreatedInstance(view)

      // Attaches an associated object to the InstanceManager to listen for when it is deallocated.
      var finalizer: TestFinalizer? = TestFinalizer()

      let key = malloc(1)!
      defer {
        free(key)
      }
      objc_setAssociatedObject(
        plugin.proxyApiRegistrar!.instanceManager, key, finalizer, .OBJC_ASSOCIATION_RETAIN)
      let expectation = self.expectation(description: "Wait for InstanceManager to be deallocated.")
      TestFinalizer.onDeinit = {
        expectation.fulfill()
      }

      // Ensure method is from `FlutterApplicationLifeCycleDelegate`.
      (plugin as FlutterApplicationLifeCycleDelegate).applicationWillTerminate!(
        UIApplication.shared)
      XCTAssertNil(plugin.proxyApiRegistrar)

      finalizer = nil
      waitForExpectations(timeout: 5.0)
    }

    func testSceneDidDisconnectKeepsRegistrarWhenRetentionEnabled() {
      WebViewFlutterPlugin.retainRegistrarOnSceneDisconnect = true
      let plugin = WebViewFlutterPlugin(binaryMessenger: TestBinaryMessenger())
      plugin.proxyApiRegistrar!.setUp()

      let scene = UIApplication.shared.connectedScenes.first!
      (plugin as FlutterSceneLifeCycleDelegate).sceneDidDisconnect?(scene)

      // Fix(kitar): 后台 scene 断开不能拆掉仍被 WKWebView 使用的 registrar。
      XCTAssertNotNil(plugin.proxyApiRegistrar)
    }

    func testInstanceManagerIsDeallocatedInSceneDidDisconnectWhenRetentionDisabled() {
      // Fix(kitar): ios_webview_protection 关闭时恢复上游拆解，测试锁住这条回滚路径。
      WebViewFlutterPlugin.retainRegistrarOnSceneDisconnect = false
      defer { WebViewFlutterPlugin.retainRegistrarOnSceneDisconnect = true }

      let plugin = WebViewFlutterPlugin(binaryMessenger: TestBinaryMessenger())
      plugin.proxyApiRegistrar!.setUp()

      let view = UIView()
      _ = plugin.proxyApiRegistrar!.instanceManager.addHostCreatedInstance(view)

      // Attaches an associated object to the InstanceManager to listen for when it is deallocated.
      var finalizer: TestFinalizer? = TestFinalizer()

      let key = malloc(1)!
      defer {
        free(key)
      }
      objc_setAssociatedObject(
        plugin.proxyApiRegistrar!.instanceManager, key, finalizer, .OBJC_ASSOCIATION_RETAIN)
      let expectation = self.expectation(description: "Wait for InstanceManager to be deallocated.")
      TestFinalizer.onDeinit = {
        expectation.fulfill()
      }

      let scene = UIApplication.shared.connectedScenes.first!

      // Ensure method is from `FlutterSceneLifeCycleDelegate`.
      (plugin as FlutterSceneLifeCycleDelegate).sceneDidDisconnect?(scene)
      XCTAssertNil(plugin.proxyApiRegistrar)

      finalizer = nil
      waitForExpectations(timeout: 5.0)
    }

    func testSceneDidDisconnectSetsTeardownImminentAndReconnectResets() {
      // Fix(kitar): scene 断开后引擎随时可能进入 destroyContext，保护开启（保留 registrar）
      // 时也必须停止 finalizer 的 removeStrongReference；scene 重连后恢复正常。
      WebViewFlutterPlugin.retainRegistrarOnSceneDisconnect = true
      WebViewFlutterPlugin.isEngineTeardownImminent = false
      defer { WebViewFlutterPlugin.isEngineTeardownImminent = false }

      let plugin = WebViewFlutterPlugin(binaryMessenger: TestBinaryMessenger())
      plugin.proxyApiRegistrar!.setUp()

      let scene = UIApplication.shared.connectedScenes.first!
      (plugin as FlutterSceneLifeCycleDelegate).sceneDidDisconnect?(scene)

      XCTAssertTrue(WebViewFlutterPlugin.isEngineTeardownImminent)
      // 保留 registrar 的保护行为不受影响。
      XCTAssertNotNil(plugin.proxyApiRegistrar)

      (plugin as FlutterSceneLifeCycleDelegate).sceneDidBecomeActive?(scene)
      XCTAssertFalse(WebViewFlutterPlugin.isEngineTeardownImminent)
    }

    func testFinalizerSkipsRemoveStrongReferenceWhenEngineTeardownImminent() {
      // Fix(kitar): 引擎 teardown 置位期间，实例 dealloc 不再发送 removeStrongReference，
      // 避免命中 FlutterEngine sendOnChannel 断言（flutter/flutter#168535）。
      WebViewFlutterPlugin.isEngineTeardownImminent = false
      defer { WebViewFlutterPlugin.isEngineTeardownImminent = false }

      let messenger = RecordingBinaryMessenger()
      let registrar = ProxyAPIRegistrar(binaryMessenger: messenger)

      // 正常状态下实例 dealloc 会发送 removeStrongReference。
      autoreleasepool {
        var view: UIView? = UIView()
        let identifier = registrar.instanceManager.addHostCreatedInstance(view!)
        let removed: AnyObject? = try? registrar.instanceManager.removeInstance(
          withIdentifier: identifier)
        _ = removed
        view = nil
      }
      XCTAssertEqual(messenger.sendCount, 1)

      // 置位期间 dealloc 的实例必须跳过发送。
      WebViewFlutterPlugin.isEngineTeardownImminent = true
      autoreleasepool {
        var view: UIView? = UIView()
        let identifier = registrar.instanceManager.addHostCreatedInstance(view!)
        let removed: AnyObject? = try? registrar.instanceManager.removeInstance(
          withIdentifier: identifier)
        _ = removed
        view = nil
      }
      XCTAssertEqual(messenger.sendCount, 1)
    }
  #endif
}

/// Fix(kitar): 记录 send 次数的 messenger，用于 finalizer 跳过发送的断言。
private class RecordingBinaryMessenger: TestBinaryMessenger {
  var sendCount = 0

  override func send(onChannel channel: String, message: Data?) {
    sendCount += 1
  }

  override func send(
    onChannel channel: String, message: Data?, binaryReply: FlutterBinaryReply? = nil
  ) {
    sendCount += 1
  }
}

class TestFinalizer {
  static var onDeinit: (() -> Void)?

  deinit {
    Self.onDeinit?()
  }
}
