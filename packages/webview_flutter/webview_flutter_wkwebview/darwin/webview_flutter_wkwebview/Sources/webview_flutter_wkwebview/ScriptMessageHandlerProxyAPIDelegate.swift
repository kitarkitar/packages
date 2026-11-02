// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import WebKit

/// Implementation of `WKScriptMessageHandler` that calls to Dart in callback methods.
class ScriptMessageHandlerImpl: NSObject, WKScriptMessageHandler {
  let api: PigeonApiProtocolWKScriptMessageHandler
  // Fix(kitar): WKUserContentController retains this handler beyond ProxyAPIRegistrar
  // teardown (detachFromEngine / applicationWillTerminate). sceneDidDisconnect no
  // longer tears the registrar down while retainRegistrarOnSceneDisconnect is true.
  // The original `unowned` aborted on the next late script message. Use a weak
  // reference and drop late messages that arrive after a real teardown.
  // https://github.com/flutter/flutter/issues/192975
  // https://github.com/flutter/flutter/issues/194340
  weak var registrar: ProxyAPIRegistrar?

  init(api: PigeonApiProtocolWKScriptMessageHandler, registrar: ProxyAPIRegistrar) {
    self.api = api
    self.registrar = registrar
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    // Fix(kitar): Messages arriving after teardown have nowhere to deliver; dropping
    // them matches the intent of `ignoreCallsToDart`.
    guard let registrar else { return }
    registrar.dispatchOnMainThread { onFailure in
      self.api.didReceiveScriptMessage(
        pigeonInstance: self, controller: userContentController, message: message
      ) { result in
        if case .failure(let error) = result {
          onFailure("WKScriptMessageHandler.didReceiveScriptMessage", error)
        }
      }
    }
  }
}

/// ProxyApi implementation for `WKScriptMessageHandler`.
///
/// This class may handle instantiating native object instances that are attached to a Dart instance
/// or handle method calls on the associated native class or an instance of that class.
class ScriptMessageHandlerProxyAPIDelegate: PigeonApiDelegateWKScriptMessageHandler {
  func pigeonDefaultConstructor(pigeonApi: PigeonApiWKScriptMessageHandler) throws
    -> WKScriptMessageHandler
  {
    return ScriptMessageHandlerImpl(
      api: pigeonApi, registrar: pigeonApi.pigeonRegistrar as! ProxyAPIRegistrar)
  }
}
