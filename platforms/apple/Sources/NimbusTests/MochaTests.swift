//
// Copyright (c) 2020, Salesforce.com, inc.
// All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
// For full license text, see the LICENSE file in the repo
// root or https://opensource.org/licenses/BSD-3-Clause
//

import JavaScriptCore
import WebKit
import XCTest
@testable import Nimbus

class MochaTests: XCTestCase, WKNavigationDelegate {
    class MochaTestBridge {
        init(webView: WKWebView) {
            self.webView = webView
        }

        let webView: WKWebView
        let expectation = XCTestExpectation(description: "testsCompleted")
        var failures: Int = -1
        func testsCompleted(failures: Int) {
            self.failures = failures
            expectation.fulfill()
        }

        func onTestFail(testTitle: String, errMessage: String) {
            NSLog("[\(testTitle)] failed: \(errMessage)")
        }

        func ready() {}
        func sendMessage(name: String, includeParam: Bool) {
            if includeParam {
                webView.broadcastMessage(name: name, arg: MochaMessage())
            } else {
                webView.broadcastMessage(name: name)
            }
        }
    }

    var webView: WKWebView!

    var loadingExpectation: XCTestExpectation?

    override func setUp() {
        webView = WKWebView()
        webView.navigationDelegate = self
    }

    override func tearDown() {
        webView.navigationDelegate = nil
        webView = nil
    }

    func loadWebViewAndWait() {
        loadingExpectation = expectation(description: "web view loaded")
        loadingExpectation?.assertForOverFulfill = false
        if let path = Bundle(for: MochaTests.self).url(forResource: "nimbus", withExtension: "js", subdirectory: "iife"),
            let nimbus = try? String(contentsOf: path) {
            let userScript = WKUserScript(source: nimbus, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(userScript)
        } else {
            // when running from swiftpm, look for the file relative to the source root
            let basepath = URL(fileURLWithPath: #file)
            let url = URL(fileURLWithPath: "../../../../packages/nimbus-bridge/dist/iife/nimbus.js", relativeTo: basepath)
            if FileManager().fileExists(atPath: url.absoluteURL.path), let script = try? String(contentsOf: url) {
                let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
                webView.configuration.userContentController.addUserScript(userScript)
            }
        }

        if let url = Bundle(for: MochaTests.self).url(forResource: "index", withExtension: "html", subdirectory: "test-www") {
            webView.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            // when running from swiftpm, look for the file relative to the source root
            let basepath = URL(fileURLWithPath: #file)
            let url = URL(fileURLWithPath: "../../../../packages/test-www/dist/test-www/index.html", relativeTo: basepath)
            if FileManager().fileExists(atPath: url.absoluteURL.path) {
                webView.loadFileURL(url.absoluteURL, allowingReadAccessTo: url.absoluteURL)
            }
        }
        wait(for: [loadingExpectation!], timeout: 5)
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        loadingExpectation?.fulfill()
    }

    // This is necessary because WebViewBridge has an optimization
    // to only add a single user script per plugin and this set of tests
    // uses WebViewConnection without WebViewBridge
    func addUserScript(connection: WebViewConnection) {
        if let script = connection.userScript() {
            let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            webView.configuration.userContentController.addUserScript(userScript)
        }
    }

    func testExecuteMochaTests() {
        let testBridge = MochaTestBridge(webView: webView)
        let webBridge = BridgeBuilder.createBridge(for: webView, plugins: [])
        let connection = WebViewConnection(from: webView, bridge: webBridge, as: "mochaTestBridge")
        connection.bind(testBridge.testsCompleted, as: "testsCompleted")
        connection.bind(testBridge.ready, as: "ready")
        connection.bind(testBridge.sendMessage, as: "sendMessage")
        connection.bind(testBridge.onTestFail, as: "onTestFail")
        addUserScript(connection: connection)
        let callbackTestPlugin = CallbackTestPlugin()
        let callbackConnection = WebViewConnection(from: webView, bridge: webBridge, as: callbackTestPlugin.namespace)
        callbackTestPlugin.bind(to: callbackConnection)
        addUserScript(connection: callbackConnection)
        let apiTestPlugin = JSAPITestPlugin()
        let apiTestConnection = WebViewConnection(from: webView, bridge: webBridge, as: apiTestPlugin.namespace)
        apiTestPlugin.bind(to: apiTestConnection)
        addUserScript(connection: apiTestConnection)

        loadWebViewAndWait()

        webView.evaluateJavaScript("""
        const titleFor = x => x.parent ? `${titleFor(x.parent)} ${x.title}` : x.title
        mocha.run(failures => { __nimbus.plugins.mochaTestBridge.testsCompleted(failures); })
             .on('fail', (test, err) => __nimbus.plugins.mochaTestBridge.onTestFail(titleFor(test), err.message));
        true;
        """) { _, error in

            if let error = error {
                XCTFail(error.localizedDescription)
            }
        }

        wait(for: [testBridge.expectation], timeout: 30)
        XCTAssertEqual(testBridge.failures, 0, "Mocha tests failed: \(testBridge.failures)")
    }
}

public class JSContextMochaTests: XCTestCase {
    var context: JSContext = JSContext()

    class JSContextMochaTestBridge {
        let context: JSContext
        let globals: JavaScriptCoreGlobalsProvider
        let expectation = XCTestExpectation(description: "testsCompleted")
        var failures: Int = -1

        init(context: JSContext) {
            self.context = context
            globals = JavaScriptCoreGlobalsProvider(context: context)
            let nimbusDeclaration = """
            __nimbus = {"plugins": {}};
            true;
            """
            context.evaluateScript(nimbusDeclaration)
        }

        func testsCompleted(failures: Int) {
            self.failures = failures
            expectation.fulfill()
        }

        func onTestFail(testTitle: String, errMessage: String) {
            NSLog("[\(testTitle)] failed: \(errMessage)")
        }

        func ready() {}
        func sendMessage(name: String, includeParam: Bool) {
            guard let broadcastFunc = context.globalObject.objectForKeyedSubscript("__nimbus")?.objectForKeyedSubscript("broadcastMessage") else {
                XCTFail("couldn't get a reference to broadcastMessage")
                return
            }
            if includeParam {
                let encodedMessage = try! JSValueEncoder().encode(MochaMessage(), context: context) // swiftlint:disable:this force_try
                broadcastFunc.call(withArguments: [name, encodedMessage])
            } else {
                broadcastFunc.call(withArguments: [name])
            }
        }
    }

    public override func setUp() {
        context = JSContext()
    }

    func evalScript(name: String, ext: String, context: JSContext) {
        if let path = Bundle(for: JSContextMochaTests.self).url(forResource: name, withExtension: ext, subdirectory: "test-www"),
            let script = try? String(contentsOf: path) {
            NSLog("eval-ing \(name).\(ext) from test-www into context")
            context.evaluateScript(script)
        } else {
            let basepath = URL(fileURLWithPath: #file)
            let url = URL(fileURLWithPath: "../../../../packages/test-www/dist/test-www/\(name).\(ext)", relativeTo: basepath)
            if FileManager().fileExists(atPath: url.absoluteURL.path), let script = try? String(contentsOf: url) {
                context.evaluateScript(script)
            }
        }
    }

    func loadContext() {
        // we might need to set something as 'global' before loading chai
        let global = context.globalObject
        context.setObject(global, forKeyedSubscript: "global" as NSString)
        context.evaluateScript("global.location = { \"search\": \"\" };")
        evalScript(name: "mocha", ext: "js", context: context)
        context.evaluateScript("mocha.reporter('json'); mocha.setup('bdd');")
        evalScript(name: "chai", ext: "js", context: context)
        evalScript(name: "bundle", ext: "js", context: context)
    }

    func testExecuteMochaTests() {
        let testBridge = JSContextMochaTestBridge(context: context)
        let contextBridge1 = BridgeBuilder.createBridge(for: JSContext(), plugins: [])
        let connection = JSContextConnection(from: context, bridge: contextBridge1, as: "mochaTestBridge")
        connection.bind(testBridge.testsCompleted, as: "testsCompleted")
        connection.bind(testBridge.ready, as: "ready")
        connection.bind(testBridge.sendMessage, as: "sendMessage")
        connection.bind(testBridge.onTestFail, as: "onTestFail")
        let callbackTestPlugin = CallbackTestPlugin()
        let contextBridge2 = BridgeBuilder.createBridge(for: JSContext(), plugins: [])
        let callbackConnection = JSContextConnection(from: context, bridge: contextBridge2, as: callbackTestPlugin.namespace)
        callbackTestPlugin.bind(to: callbackConnection)
        let apiTestPlugin = JSAPITestPlugin()
        let contextBridge3 = BridgeBuilder.createBridge(for: JSContext(), plugins: [])
        let apiTestConnection = JSContextConnection(from: context, bridge: contextBridge3, as: apiTestPlugin.namespace)
        apiTestPlugin.bind(to: apiTestConnection)

        loadContext()

        let testScript = """
        const titleFor = x => x.parent ? `${titleFor(x.parent)} ${x.title}` : x.title
        mocha.run(failures => { __nimbus.plugins.mochaTestBridge.testsCompleted(failures); })
             .on('fail', (test, err) => __nimbus.plugins.mochaTestBridge.onTestFail(titleFor(test), err.message));
        true;
        """

        let evalResult = context.evaluateScript(testScript)

        wait(for: [testBridge.expectation], timeout: 30)
        XCTAssertNotNil(evalResult, "test script failed to execute")
        XCTAssertEqual(testBridge.failures, 0, "Mocha tests failed: \(testBridge.failures)")
    }
}

struct MochaMessage: Encodable {
    var stringField = "This is a string"
    var intField = 42
}

public struct TestError: Error, Encodable {
    let code: Int
    let message: String
}

public class CallbackTestPlugin {
    func callbackWithSingleParam(completion: @escaping (MochaMessage) -> Swift.Void) {
        let mochaMessage = MochaMessage()
        completion(mochaMessage)
    }

    func callbackWithTwoParams(completion: @escaping (MochaMessage, MochaMessage) -> Swift.Void) {
        var mochaMessage = MochaMessage()
        mochaMessage.intField = 6
        mochaMessage.stringField = "int param is 6"
        completion(MochaMessage(), mochaMessage)
    }

    func callbackWithSinglePrimitiveParam(completion: @escaping (Int) -> Swift.Void) {
        completion(777)
    }

    func callbackWithTwoPrimitiveParams(completion: @escaping (Int, Int) -> Swift.Void) {
        completion(777, 888)
    }

    func callbackWithPrimitiveAndUddtParams(completion: @escaping (Int, MochaMessage) -> Swift.Void) {
        completion(777, MochaMessage())
    }

    func promiseResolved() -> String {
        return "promise"
    }

    func promiseRejectedEncoded() throws -> String {
        throw TestError(code: 42, message: "mock promise rejection")
    }

    func promiseRejected() throws -> String {
        throw MockError.rejectedError
    }
}

enum MockError: Error {
    case rejectedError
}

extension CallbackTestPlugin: Plugin {
    public var namespace: String {
        return "callbackTestPlugin"
    }

    public func bind<C>(to connection: C) where C: Connection {
        connection.bind(callbackWithSingleParam, as: "callbackWithSingleParam")
        connection.bind(callbackWithTwoParams, as: "callbackWithTwoParams")
        connection.bind(callbackWithSinglePrimitiveParam, as: "callbackWithSinglePrimitiveParam")
        connection.bind(callbackWithTwoPrimitiveParams, as: "callbackWithTwoPrimitiveParams")
        connection.bind(callbackWithPrimitiveAndUddtParams, as: "callbackWithPrimitiveAndUddtParams")
        connection.bind(promiseResolved, as: "promiseResolved")
        connection.bind(promiseRejectedEncoded, as: "promiseRejectedEncoded")
        connection.bind(promiseRejected, as: "promiseRejected")
    }
}

class JSAPITestPlugin: Plugin {
    func nullaryResolvingToInt() -> Int {
        return 5
    }

    func nullaryResolvingToIntArray() -> [Int] {
        return [1, 2, 3]
    }

    func nullaryResolvingToObject() -> JSAPITestStruct {
        return JSAPITestStruct()
    }

    func unaryResolvingToVoid(param: Int) {
        XCTAssertEqual(param, 5)
    }

    func unaryObjectResolvingToVoid(param: JSAPITestStruct) {
        XCTAssertEqual(param, JSAPITestStruct())
    }

    func binaryResolvingToIntCallback(param: Int, completion: (Int) -> Void) {
        XCTAssertEqual(param, 5)
        completion(5)
    }

    func binaryResolvingToObjectCallback(param: Int, completion: (JSAPITestStruct) -> Void) {
        XCTAssertEqual(param, 5)
        completion(JSAPITestStruct())
    }

    func binaryResolvingToObjectCallbackToInt(param: Int, completion: (JSAPITestStruct) -> Void) -> Int {
        XCTAssertEqual(param, 5)
        completion(.init())
        return 1
    }

    var namespace: String {
        return "jsapiTestPlugin"
    }

    func bind<C>(to connection: C) where C: Connection {
        connection.bind(nullaryResolvingToInt, as: "nullaryResolvingToInt")
        connection.bind(nullaryResolvingToIntArray, as: "nullaryResolvingToIntArray")
        connection.bind(nullaryResolvingToObject, as: "nullaryResolvingToObject")
        connection.bind(unaryResolvingToVoid, as: "unaryResolvingToVoid")
        connection.bind(unaryObjectResolvingToVoid, as: "unaryObjectResolvingToVoid")
        connection.bind(binaryResolvingToIntCallback, as: "binaryResolvingToIntCallback")
        connection.bind(binaryResolvingToObjectCallback, as: "binaryResolvingToObjectCallback")
        connection.bind(binaryResolvingToObjectCallbackToInt, as: "binaryResolvingToObjectCallbackToInt")
    }

    struct JSAPITestStruct: Codable, Equatable {
        let intField = 42
        let stringField = "JSAPITEST"
    }
}
