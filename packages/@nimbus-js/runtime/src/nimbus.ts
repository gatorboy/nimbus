import { Nimbus } from "@nimbus-js/api";

declare global {
  interface NimbusNative {
    makeCallback(callbackId: string): any;
    nativePluginNames(): string;
    pageUnloaded(): void;
  }
  var _nimbus: NimbusNative;
  var __nimbusPluginExports: { [s: string]: string[] };

  interface Window {
    [s: string]: any;
  }
}

let plugins: { [s: string]: any } = {};

// Store promise functions for later invocation
let uuidsToPromises: {
  [s: string]: { resolve: Function; reject: Function };
} = {};

// Store callback functions for later invocation
let uuidsToCallbacks: { [s: string]: Function } = {};

// Store event listener functions for later invocation
let eventNameToListeners: { [s: string]: Function[] } = {};

// influenced from
// https://stackoverflow.com/questions/105034/create-guid-uuid-in-javascript
let uuidv4 = (): string => {
  return "10000000-1000-4000-8000-100000000000".replace(
    /[018]/g,
    (c): string => {
      const asNumber = Number(c);
      return (
        asNumber ^
        (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (asNumber / 4)))
      ).toString(16);
    }
  );
};

let cloneArguments = (args: any[]): any[] => {
  let clonedArgs = [];
  for (var i = 0; i < args.length; ++i) {
    if (typeof args[i] === "function") {
      const callbackId = uuidv4();
      uuidsToCallbacks[callbackId] = args[i];
      clonedArgs.push(callbackId);
    } else if (typeof args[i] === "object") {
      clonedArgs.push(JSON.stringify(args[i]));
    } else {
      clonedArgs.push(args[i]);
    }
  }
  return clonedArgs;
};

let promisify = (src: any): void => {
  let dest: any = {};
  Object.keys(src).forEach((key): void => {
    let func = src[key];
    dest[key] = (...args: any[]): Promise<any> => {
      args = cloneArguments(args);

      return new Promise(function (resolve, reject): void {
        var promiseId = uuidv4();
        uuidsToPromises[promiseId] = { resolve, reject };
        try {
          func.call(src, JSON.stringify({ promiseId }), ...args);
        } catch (error) {
          delete uuidsToPromises[promiseId];
          reject(error);
        }
      });
    };
  });
  return dest;
};

let callCallback = (callbackId: string, ...args: any[]): void => {
  if (uuidsToCallbacks[callbackId]) {
    uuidsToCallbacks[callbackId](...args);
  }
};

let releaseCallback = (callbackId: string): void => {
  delete uuidsToCallbacks[callbackId];
};

// Native side will callback this method. Match the callback to stored promise
// in the storage
let resolvePromise = (promiseUuid: string, data: any, error: any): void => {
  if (error) {
    uuidsToPromises[promiseUuid].reject(error);
  } else {
    uuidsToPromises[promiseUuid].resolve(data);
  }
  // remove reference to stored promise
  delete uuidsToPromises[promiseUuid];
};

let broadcastMessage = (message: string, arg: any): number => {
  let messageListeners = eventNameToListeners[message];
  var handlerCallCount = 0;
  if (messageListeners) {
    messageListeners.forEach((listener: any): void => {
      if (arg) {
        listener(arg);
      } else {
        listener();
      }
      handlerCallCount++;
    });
  }
  return handlerCallCount;
};

let subscribeMessage = (message: string, listener: Function): void => {
  let messageListeners = eventNameToListeners[message];
  if (!messageListeners) {
    messageListeners = [];
  }
  messageListeners.push(listener);
  eventNameToListeners[message] = messageListeners;
};

let unsubscribeMessage = (message: string, listener: Function): void => {
  let messageListeners = eventNameToListeners[message];
  if (messageListeners) {
    let counter = 0;
    let found = false;
    for (counter; counter < messageListeners.length; counter++) {
      if (messageListeners[counter] === listener) {
        found = true;
        break;
      }
    }
    if (found) {
      messageListeners.splice(counter, 1);
      eventNameToListeners[message] = messageListeners;
    }
  }
};

// Android plugin import
if (typeof _nimbus !== "undefined" && _nimbus.nativePluginNames !== undefined) {
  // we're on Android, need to wrap native extension methods
  let extensionNames = JSON.parse(_nimbus.nativePluginNames());
  extensionNames.forEach((extension: string): void => {
    Object.assign(plugins, {
      [extension]: Object.assign(
        plugins[`${extension}`] || {},
        promisify(window[`_${extension}`])
      ),
    });
  });
}

// iOS plugin import
if (typeof __nimbusPluginExports !== "undefined") {
  Object.keys(__nimbusPluginExports).forEach((pluginName: string): void => {
    let plugin = {};
    __nimbusPluginExports[pluginName].forEach((method: string): void => {
      Object.assign(plugin, {
        [method]: function (): Promise<any> {
          let functionArgs = cloneArguments(Array.from(arguments));
          return new Promise(function (resolve, reject): void {
            var promiseId = uuidv4();
            uuidsToPromises[promiseId] = { resolve, reject };
            window.webkit.messageHandlers[pluginName].postMessage({
              method: method,
              args: functionArgs,
              promiseId: promiseId,
            });
          });
        },
      });
    });
    Object.assign(plugins, {
      [pluginName]: plugin,
    });
  });
}

let nimbusBuilder = {
  plugins: plugins,
};

Object.defineProperties(nimbusBuilder, {
  callCallback: {
    value: callCallback,
  },
  releaseCallback: {
    value: releaseCallback,
  },
  resolvePromise: {
    value: resolvePromise,
  },
  broadcastMessage: {
    value: broadcastMessage,
  },
  subscribeMessage: {
    value: subscribeMessage,
  },
  unsubscribeMessage: {
    value: unsubscribeMessage,
  },
});

let nimbus: Nimbus = nimbusBuilder as Nimbus;

// When the page unloads, reject all Promises for native-->web calls.
window.addEventListener("unload", (): void => {
  if (typeof _nimbus !== "undefined") {
    _nimbus.pageUnloaded();
  } else if (typeof window.webkit !== "undefined") {
    window.webkit.messageHandlers._nimbus.postMessage({
      method: "pageUnloaded",
    });
  }
});

window.__nimbus = nimbus;

export default nimbus;

// TODO:
// var __nimbus = (function () {})();