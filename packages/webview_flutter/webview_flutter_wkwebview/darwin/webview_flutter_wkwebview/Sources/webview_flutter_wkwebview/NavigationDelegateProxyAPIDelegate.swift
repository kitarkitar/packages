// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import WebKit

/// Remote Config `ios_webview_protection`。false 时 NSNull 判断、completion 补调、
/// scene 断开保留 registrar 都回到插件原始行为。
public enum KitarWebviewProtection {
  public static var isEnabled = true
}

/// 最多调用一次的 completion。释放时仍未回调则补一次安全默认值，
/// 避免引擎 destroyContext 丢掉 WK completion 后 WebKit abort。
final class KitarOnceCompletion<T> {
  private var handler: ((T) -> Void)?
  private let fallback: T

  init(_ handler: @escaping (T) -> Void, fallback: T) {
    self.handler = handler
    self.fallback = fallback
  }

  func call(_ value: T) {
    guard let handler else { return }
    self.handler = nil
    handler(value)
  }

  deinit {
    guard let handler else { return }
    self.handler = nil
    NSLog("KitarOnceCompletion fallback invoked")
    handler(fallback)
  }
}

/// Implementation of `WKNavigationDelegate` that calls to Dart in callback methods.
public class NavigationDelegateImpl: NSObject, WKNavigationDelegate {
  let api: PigeonApiProtocolWKNavigationDelegate
  unowned let registrar: ProxyAPIRegistrar

  init(api: PigeonApiProtocolWKNavigationDelegate, registrar: ProxyAPIRegistrar) {
    self.api = api
    self.registrar = registrar
  }

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    registrar.dispatchOnMainThread { onFailure in
      self.api.didFinishNavigation(
        pigeonInstance: self, webView: webView, url: webView.url?.absoluteString
      ) { result in
        if case .failure(let error) = result {
          onFailure("WKNavigationDelegate.didFinishNavigation", error)
        }
      }
    }
  }

  public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!)
  {
    registrar.dispatchOnMainThread { onFailure in
      self.api.didStartProvisionalNavigation(
        pigeonInstance: self, webView: webView, url: webView.url?.absoluteString
      ) { result in
        if case .failure(let error) = result {
          onFailure("WKNavigationDelegate.didStartProvisionalNavigation", error)
        }
      }
    }
  }

  public func webView(
    _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
  ) {
    registrar.dispatchOnMainThread { onFailure in
      self.api.didFailNavigation(pigeonInstance: self, webView: webView, error: error as NSError) {
        result in
        if case .failure(let error) = result {
          onFailure("WKNavigationDelegate.didFailNavigation", error)
        }
      }
    }
  }

  public func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    registrar.dispatchOnMainThread { onFailure in
      self.api.didFailProvisionalNavigation(
        pigeonInstance: self, webView: webView, error: error as NSError
      ) { result in
        if case .failure(let error) = result {
          onFailure("WKNavigationDelegate.didFailProvisionalNavigation", error)
        }
      }
    }
  }

  public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    registrar.dispatchOnMainThread { onFailure in
      self.api.webViewWebContentProcessDidTerminate(pigeonInstance: self, webView: webView) {
        result in
        if case .failure(let error) = result {
          onFailure("WKNavigationDelegate.webViewWebContentProcessDidTerminate", error)
        }
      }
    }
  }

  #if compiler(>=6.0)
    public func webView(
      _ webView: WKWebView, decidePolicyFor navigationAction: WebKit.WKNavigationAction,
      decisionHandler: @escaping @MainActor (WebKit.WKNavigationActionPolicy) -> Void
    ) {
      // Fix(kitar): 参数标签属于 ObjC selector，不可改名。引擎销毁丢掉回包时补 cancel。
      let kitarDecision: @MainActor (WebKit.WKNavigationActionPolicy) -> Void
      if KitarWebviewProtection.isEnabled {
        let kitarBox = KitarOnceCompletion(
          decisionHandler, fallback: WebKit.WKNavigationActionPolicy.cancel)
        kitarDecision = { kitarBox.call($0) }
      } else {
        kitarDecision = decisionHandler
      }
      registrar.dispatchOnMainThread { onFailure in
        self.api.decidePolicyForNavigationAction(
          pigeonInstance: self, webView: webView, navigationAction: navigationAction
        ) { result in
          DispatchQueue.main.async {
            switch result {
            case .success(let policy):
              switch policy {
              case .allow:
                kitarDecision(.allow)
              case .cancel:
                kitarDecision(.cancel)
              case .download:
                if #available(iOS 14.5, macOS 11.3, *) {
                  kitarDecision(.download)
                } else {
                  kitarDecision(.cancel)
                  assertionFailure(
                    self.registrar.createUnsupportedVersionMessage(
                      "WKNavigationActionPolicy.download",
                      versionRequirements: "iOS 14.5, macOS 11.3"
                    ))
                }
              }
            case .failure(let error):
              kitarDecision(.cancel)
              onFailure("WKNavigationDelegate.decidePolicyForNavigationAction", error)
            }
          }
        }
      }
    }
  #else
    public func webView(
      _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      // Fix(kitar): 参数标签属于 ObjC selector，不可改名。引擎销毁丢掉回包时补 cancel。
      let kitarDecision: (WKNavigationActionPolicy) -> Void
      if KitarWebviewProtection.isEnabled {
        let kitarBox = KitarOnceCompletion(
          decisionHandler, fallback: WKNavigationActionPolicy.cancel)
        kitarDecision = { kitarBox.call($0) }
      } else {
        kitarDecision = decisionHandler
      }
      registrar.dispatchOnMainThread { onFailure in
        self.api.decidePolicyForNavigationAction(
          pigeonInstance: self, webView: webView, navigationAction: navigationAction
        ) { result in
          DispatchQueue.main.async {
            switch result {
            case .success(let policy):
              switch policy {
              case .allow:
                kitarDecision(.allow)
              case .cancel:
                kitarDecision(.cancel)
              case .download:
                if #available(iOS 14.5, macOS 11.3, *) {
                  kitarDecision(.download)
                } else {
                  kitarDecision(.cancel)
                  assertionFailure(
                    self.registrar.createUnsupportedVersionMessage(
                      "WKNavigationActionPolicy.download",
                      versionRequirements: "iOS 14.5, macOS 11.3"
                    ))
                }
              }
            case .failure(let error):
              kitarDecision(.cancel)
              onFailure("WKNavigationDelegate.decidePolicyForNavigationAction", error)
            }
          }
        }
      }
    }
  #endif

  #if compiler(>=6.0)
    public func webView(
      _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
      decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
      // Fix(kitar): 参数标签属于 ObjC selector，不可改名。引擎销毁丢掉回包时补 cancel。
      let kitarDecision: @MainActor (WKNavigationResponsePolicy) -> Void
      if KitarWebviewProtection.isEnabled {
        let kitarBox = KitarOnceCompletion(
          decisionHandler, fallback: WKNavigationResponsePolicy.cancel)
        kitarDecision = { kitarBox.call($0) }
      } else {
        kitarDecision = decisionHandler
      }
      registrar.dispatchOnMainThread { onFailure in
        self.api.decidePolicyForNavigationResponse(
          pigeonInstance: self, webView: webView, navigationResponse: navigationResponse
        ) { result in
          DispatchQueue.main.async {
            switch result {
            case .success(let policy):
              switch policy {
              case .allow:
                kitarDecision(.allow)
              case .cancel:
                kitarDecision(.cancel)
              case .download:
                if #available(iOS 14.5, macOS 11.3, *) {
                  kitarDecision(.download)
                } else {
                  kitarDecision(.cancel)
                  assertionFailure(
                    self.registrar.createUnsupportedVersionMessage(
                      "WKNavigationResponsePolicy.download",
                      versionRequirements: "iOS 14.5, macOS 11.3"
                    ))
                }
              }
            case .failure(let error):
              kitarDecision(.cancel)
              onFailure("WKNavigationDelegate.decidePolicyForNavigationResponse", error)
            }
          }
        }
      }
    }
  #else
    public func webView(
      _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
      decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
      // Fix(kitar): 参数标签属于 ObjC selector，不可改名。引擎销毁丢掉回包时补 cancel。
      let kitarDecision: (WKNavigationResponsePolicy) -> Void
      if KitarWebviewProtection.isEnabled {
        let kitarBox = KitarOnceCompletion(
          decisionHandler, fallback: WKNavigationResponsePolicy.cancel)
        kitarDecision = { kitarBox.call($0) }
      } else {
        kitarDecision = decisionHandler
      }
      registrar.dispatchOnMainThread { onFailure in
        self.api.decidePolicyForNavigationResponse(
          pigeonInstance: self, webView: webView, navigationResponse: navigationResponse
        ) { result in
          DispatchQueue.main.async {
            switch result {
            case .success(let policy):
              switch policy {
              case .allow:
                kitarDecision(.allow)
              case .cancel:
                kitarDecision(.cancel)
              case .download:
                if #available(iOS 14.5, macOS 11.3, *) {
                  kitarDecision(.download)
                } else {
                  kitarDecision(.cancel)
                  assertionFailure(
                    self.registrar.createUnsupportedVersionMessage(
                      "WKNavigationResponsePolicy.download",
                      versionRequirements: "iOS 14.5, macOS 11.3"
                    ))
                }
              }
            case .failure(let error):
              kitarDecision(.cancel)
              onFailure("WKNavigationDelegate.decidePolicyForNavigationResponse", error)
            }
          }
        }
      }
    }
  #endif

  #if compiler(>=6.0)
    public func webView(
      _ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
      completionHandler:
        @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?)
        ->
        Void
    ) {
      // Fix(kitar): 参数标签属于 ObjC selector，不可改名。引擎销毁丢掉回包时补 cancel。
      let kitarCompletion: @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
      if KitarWebviewProtection.isEnabled {
        let kitarAuthBox = KitarOnceCompletion<(URLSession.AuthChallengeDisposition, URLCredential?)>(
          { disposition, credential in completionHandler(disposition, credential) },
          fallback: (.cancelAuthenticationChallenge, nil))
        kitarCompletion = { disposition, credential in
          kitarAuthBox.call((disposition, credential))
        }
      } else {
        kitarCompletion = completionHandler
      }
      registrar.dispatchOnMainThread { onFailure in
        self.api.didReceiveAuthenticationChallenge(
          pigeonInstance: self, webView: webView, challenge: challenge
        ) { result in
          DispatchQueue.main.async {
            switch result {
            case .success(let response):
              kitarCompletion(response.disposition, response.credential)
            case .failure(let error):
              // Fix(kitar): 实例丢失（null-error）时走 performDefaultHandling，
              // cancel 会让直播 HTTPS 页打不开。保护关闭时保持原始 cancel。
              if KitarWebviewProtection.isEnabled && error.code == "null-error" {
                kitarCompletion(.performDefaultHandling, nil)
              } else {
                kitarCompletion(.cancelAuthenticationChallenge, nil)
              }
              onFailure("WKNavigationDelegate.didReceiveAuthenticationChallenge", error)
            }
          }
        }
      }
    }
  #else
    public func webView(
      _ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
      completionHandler:
        @escaping (URLSession.AuthChallengeDisposition, URLCredential?) ->
        Void
    ) {
      // Fix(kitar): 参数标签属于 ObjC selector，不可改名。引擎销毁丢掉回包时补 cancel。
      let kitarCompletion: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
      if KitarWebviewProtection.isEnabled {
        let kitarAuthBox = KitarOnceCompletion<(URLSession.AuthChallengeDisposition, URLCredential?)>(
          { disposition, credential in completionHandler(disposition, credential) },
          fallback: (.cancelAuthenticationChallenge, nil))
        kitarCompletion = { disposition, credential in
          kitarAuthBox.call((disposition, credential))
        }
      } else {
        kitarCompletion = completionHandler
      }
      registrar.dispatchOnMainThread { onFailure in
        self.api.didReceiveAuthenticationChallenge(
          pigeonInstance: self, webView: webView, challenge: challenge
        ) { result in
          DispatchQueue.main.async {
            switch result {
            case .success(let response):
              kitarCompletion(response.disposition, response.credential)
            case .failure(let error):
              // Fix(kitar): 实例丢失（null-error）时走 performDefaultHandling，
              // cancel 会让直播 HTTPS 页打不开。保护关闭时保持原始 cancel。
              if KitarWebviewProtection.isEnabled && error.code == "null-error" {
                kitarCompletion(.performDefaultHandling, nil)
              } else {
                kitarCompletion(.cancelAuthenticationChallenge, nil)
              }
              onFailure("WKNavigationDelegate.didReceiveAuthenticationChallenge", error)
            }
          }
        }
      }
    }
  #endif
}

/// ProxyApi implementation for `WKNavigationDelegate`.
///
/// This class may handle instantiating native object instances that are attached to a Dart instance
/// or handle method calls on the associated native class or an instance of that class.
class NavigationDelegateProxyAPIDelegate: PigeonApiDelegateWKNavigationDelegate {
  func pigeonDefaultConstructor(pigeonApi: PigeonApiWKNavigationDelegate) throws
    -> WKNavigationDelegate
  {
    return NavigationDelegateImpl(
      api: pigeonApi, registrar: pigeonApi.pigeonRegistrar as! ProxyAPIRegistrar)
  }
}
