//
//  JavaScriptNetworking.swift
//  CruxPay
//
//  Created by Sanchay on 19/11/19.
//

import Foundation
import JavaScriptCore
import os

class JSFetch {
    
    static var authorizationHeader: String?
    
    private static let fetch: @convention(block) (Any, Any) -> (Any) = { (url: Any, settings: Any) in
        // Check our arguments
        var xsettings = settings as! Dictionary<String, Any>
        if (xsettings["method"] == nil)  {
            xsettings["method"] = "GET"
        }
        guard let urlString = url as? String,
            let url = URL(string: urlString),
            let settings = xsettings as? NSDictionary,
            let method = settings["method"] as? String else {
                os_log("Failure: Incorrect arguments", log: OSLog.default, type: .error)
                return JSContext.current().evaluateScript("Promise.reject(\"Incorrect arguments. Expected a URL and settings object.\");")!
        }
        
        // Make the request within the promise block
        let globalPromise = JSContext.current().evaluateScript("Promise")!
        let promiseBlock: @convention(block) (JavaScriptCore.JSValue, JavaScriptCore.JSValue) -> () = { (resolve, reject) in
            let session = URLSession.shared
            var request = URLRequest(url: url)
            request.httpMethod = method
            if let credentials = settings["credentials"] as? String, credentials == "include", let auth = JSFetch.authorizationHeader {
                request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            let headers = (settings["headers"] as? NSDictionary) as? NSDictionary ?? [:]
            for key in headers.allKeys {
                if let value = headers[key] as? String, let key = key as? String {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
            if let body = settings["body"] as? String {
                request.httpBody = body.data(using: .utf8)
            }
            
            let context = JSContext.current()!
            let dataTask = session.dataTask(with: request, completionHandler: { (data, response, error) in
                if let error = error {
                    os_log("Failure:", log: OSLog.default, type: .error)
                    let jsError = context.evaluateScript("new Error(\"\(error.localizedDescription)\");")!
                    reject.call(withArguments: [jsError])
                } else if let data = data {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let body = (String(data: data, encoding: .ascii) ?? "")
                    let httpResponse = response as! HTTPURLResponse
                    let globalHeaders = context.evaluateScript("Headers;")
                    let headers = globalHeaders!.construct(withArguments: [])!
                    let globalResponse = context.evaluateScript("Response;")!
                    var response: JavaScriptCore.JSValue
                    response = globalResponse.construct(withArguments: [urlString, code, body, headers])!
                    if !(code >= 200 && code < 300) {
                        os_log("Request denied: %d %s", log: OSLog.default, type: .error, code, body)
                    }
                    resolve.call(withArguments: [response])
                }
            })
            dataTask.resume()
            os_log("Requesting: %s %s", log: OSLog.default, type: .debug, urlString, method)
        }
        
        JSContext.current().setObject(promiseBlock, forKeyedSubscript: "JavaScriptNetworkingPromiseBridgeHelper" as NSString)
        let promise = globalPromise.construct(withArguments: [JSContext.current()!.objectForKeyedSubscript("JavaScriptNetworkingPromiseBridgeHelper")!])
        JSContext.current().setObject(JSValue.init(nullIn: JSContext.current()), forKeyedSubscript: "JavaScriptNetworkingPromiseBridgeHelper" as NSString)
        return promise!
    }
    
    class func provideToContext(context: JSContext) {
        context.setObject(self.fetch, forKeyedSubscript: "fetch" as NSString)
    }
    
}
