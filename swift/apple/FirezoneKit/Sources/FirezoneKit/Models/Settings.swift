//
//  Settings.swift
//  (c) 2024 Firezone, Inc.
//  LICENSE: Apache-2.0
//

import Foundation

struct Settings: Equatable {
  var authBaseURL: String
  var apiURL: String
  var logFilter: String
  var disabledResources: Set<String>

  var isValid: Bool {
    let authBaseURL = URL(string: authBaseURL)
    let apiURL = URL(string: apiURL)
    // Technically strings like "foo" are valid URLs, but their host component
    // would be nil which crashes the ASWebAuthenticationSession view when
    // signing in. We should also validate the scheme, otherwise ftp://
    // could be used for example which tries to open the Finder when signing
    // in. 🙃
    return authBaseURL?.host != nil
      && apiURL?.host != nil
      && ["http", "https"].contains(authBaseURL?.scheme)
      && ["ws", "wss"].contains(apiURL?.scheme)
      && !logFilter.isEmpty
  }


  // Convert provider configuration (which may have empty fields if it was tampered with) to Settings
  static func fromProviderConfiguration(_ providerConfiguration: [String: Any]?) -> Settings {
    if let providerConfiguration = providerConfiguration as? [String: String] {
      return Settings(
        authBaseURL: providerConfiguration[TunnelManagerKeys.authBaseURL]
          ?? Settings.defaultValue.authBaseURL,
        apiURL: providerConfiguration[TunnelManagerKeys.apiURL]
          ?? Settings.defaultValue.apiURL,
        logFilter: providerConfiguration[TunnelManagerKeys.logFilter]
          ?? Settings.defaultValue.logFilter,
        disabledResources: getDisabledResources(disabledResources: providerConfiguration[TunnelManagerKeys.disabledResources])
      )
    } else {
      return Settings.defaultValue
    }
  }

  static private func getDisabledResources(disabledResources: String?) -> Set<String> {
    guard let disabledResourcesJSON = disabledResources, let disabledResourcesData = disabledResourcesJSON.data(using: .utf8)  else{
      return Set()
    }
    return (try? JSONDecoder().decode(Set<String>.self, from: disabledResourcesData))
      ?? Settings.defaultValue.disabledResources
  }

  // Used for initializing a new providerConfiguration from Settings
  func toProviderConfiguration() -> [String: String] {
    return [
      TunnelManagerKeys.authBaseURL: authBaseURL,
      TunnelManagerKeys.apiURL: apiURL,
      TunnelManagerKeys.logFilter: logFilter,
      TunnelManagerKeys.disabledResources: String(data: try! JSONEncoder().encode(disabledResources), encoding: .utf8) ?? "",
    ]
  }

  static let defaultValue: Settings = {
    // Note: To see what the connlibLogFilterString values mean, see:
    // https://docs.rs/tracing-subscriber/latest/tracing_subscriber/filter/struct.EnvFilter.html
    #if DEBUG
      Settings(
        authBaseURL: "https://app.firez.one",
        apiURL: "wss://api.firez.one",
        logFilter:
          "firezone_tunnel=debug,phoenix_channel=debug,connlib_shared=debug,connlib_client_shared=debug,snownet=debug,str0m=info,warn",
        disabledResources: Set()
      )
    #else
      Settings(
        authBaseURL: "https://app.firezone.dev",
        apiURL: "wss://api.firezone.dev",
        logFilter: "str0m=warn,info",
        disabledResources: Set()
      )
    #endif
  }()
}

extension Settings: CustomStringConvertible {
  var description: String {
    "(\(authBaseURL), \(apiURL), \(logFilter)"
  }
}
