//
//  SettingsService.swift
//  MixpanelSessionReplay
//

import Foundation

struct SettingsCacheKeys {
    static func configuration(for token: String) -> String {
        return "mp_sr_recording_settings_config_\(token)"
    }

    static func timestamp(for token: String) -> String {
        return "mp_sr_recording_timestamp_\(token)"
    }
}

class SettingsService {
    private let network: Network
    private let version: String
    private let mpLib: String
    private let userDefaults: UserDefaults

    static let settingsTimeoutMS = 5.0

    init(
        network: Network = Network(), version: String, mpLib: String,
        userDefaults: UserDefaults = UserDefaults(suiteName: ReplaySettings.userDefaultsName) ?? UserDefaults.standard
    ) {
        self.network = network
        self.version = version
        self.userDefaults = userDefaults
        self.mpLib = mpLib
    }

    func getRemoteConfiguration(
        token: String,
        mode: RemoteSettingsMode,
        originalConfig: MPSessionReplayConfig,
        completion: @escaping (SettingsResponse?, MPSessionReplayConfig) -> Void
    ) {
        fetchSettingsFromServer(token: token) { [weak self] result in
            switch result {
                case .success(let settings):
                    // Handle disabled mode: If the remote settings are disabled, we still fetch the remote settings
                    // to get the isRecording(remote enablement switch) flag, but we do not merge the configs with the original config.
                    if mode == .disabled {
                        Logger.info(message: "Remote settings mode is disabled, using original config")
                        // Remove the sdkConfig from the settings response to prevent any accidental usage of remote sdk config values in disabled mode, but keep the recording settings to respect remote enablement switch if present in remote settings
                        let updatedSettings = SettingsResponse(sdkConfig: nil, recording: settings.recording)
                        completion(updatedSettings, originalConfig)
                        return
                    }
                    // Merge remote settings with original config
                    let updatedConfig =
                        self?.mergeConfigs(
                            original: originalConfig,
                            remote: settings
                        ) ?? originalConfig
                    completion(settings, updatedConfig)

                case .failure(let error):
                    Logger.error(message: "Remote Settings API failed: \(error.localizedDescription)")
                    self?.handleFailure(
                        error: error,
                        mode: mode,
                        token: token,
                        originalConfig: originalConfig,
                        completion: completion
                    )
            }
        }
    }

    private func fetchSettingsFromServer(token: String, completion: @escaping (Result<SettingsResponse, Error>) -> Void)
    {
        Logger.info(message: "Checking remote settings for project: \(token)")

        let queryItems = [
            URLQueryItem(name: "recording", value: "1"),
            URLQueryItem(name: "sdk_config", value: "1"),
            URLQueryItem(name: "mp_lib", value: mpLib),
            URLQueryItem(name: "$lib_version", value: version),
            URLQueryItem(name: "$os", value: "iOS"),
        ]

        var headers = [String: String]()
        if let data = "\(token):".data(using: .utf8) {
            headers["Authorization"] = "Basic \(data.base64EncodedString())"
        }

        let apiRequest = APIRequest(
            endPoint: MPSessionReplayAPI.settingsEndpoint,
            method: .get,
            requestBody: nil,
            queryItems: queryItems,
            headers: headers,
            timeoutInterval: Self.settingsTimeoutMS
        )

        // Make the network request AFTER setting timeout
        network.sendDecodableRequest(apiRequest, responseType: SettingsResponse.self) { result in
            switch result {
                case .success(let response):
                    self.handleSuccessResponse(response: response, token: token, completion: completion)
                case .failure(let error):
                    self.handleErrorResponse(error: error, token: token, completion: completion)
            }
        }
    }

    // MARK: Handle settings response
    private func handleSuccessResponse(
        response: SettingsResponse, token: String, completion: @escaping (Result<SettingsResponse, Error>) -> Void
    ) {
        Logger.debug(message: "Remote Settings API Success response: \(response)")
        //Save the response for later use
        cacheSettingsState(settingConfig: response, token: token)
        completion(.success(response))
    }

    private func handleErrorResponse(
        error: Error, token: String, completion: @escaping (Result<SettingsResponse, Error>) -> Void
    ) {
        let errorMessage = error.localizedDescription
        Logger.warn(message: "Remote Settings API error: \(errorMessage) -- checking cache...")
        completion(.failure(error))
    }

    private func handleFailure(
        error: Error,
        mode: RemoteSettingsMode,
        token: String,
        originalConfig: MPSessionReplayConfig,
        completion: @escaping (SettingsResponse?, MPSessionReplayConfig) -> Void
    ) {
        switch mode {
            case .strict:
                // Strict mode: disable SDK initialization
                Logger.warn(message: "Strict mode: Remote settings fetch failed, disabling SDK initialization")
                completion(nil, originalConfig)

            case .fallback:
                // Fallback mode: Use cached or original config
                Logger.info(message: "Fallback mode: Using cached settings or original config")
                let cachedSettings = getCachedSettingsState(token: token)
                let config = mergeConfigs(original: originalConfig, remote: cachedSettings)
                completion(cachedSettings, config)

            case .disabled:
                // Disabled mode: use the cached settings without merging to check remote enablement switch
                let cachedSettings = getCachedSettingsState(token: token)
                Logger.warn(message: "Disabled mode: Using cached setting for remote enablement switch check")
                completion(cachedSettings, originalConfig)
        }
    }

    // MARK: Apply remote configurations
    private func mergeConfigs(
        original: MPSessionReplayConfig,
        remote: SettingsResponse?
    ) -> MPSessionReplayConfig {
        var updated = original

        // Apply remote SDK config if available
        if let sdkConfig = remote?.sdkConfig?.config {
            Logger.info(message: "Merging remote SDK config with original config")

            if let recordSessionsPercent = sdkConfig.recordSessionsPercent {
                if (0.0...100.0).contains(recordSessionsPercent) {
                    Logger.debug(message: "Applying remote recordSessionsPercent: \(recordSessionsPercent)")
                    updated.recordingSessionsPercent = recordSessionsPercent
                } else {
                    Logger.warn(message: "Received invalid value for recordSessionsPercent, \(recordSessionsPercent)")
                }
            } else {
                Logger.warn(message: "recordSessionsPercent is not present in remote settings SDK config")
            }
        } else {
            Logger.warn(message: "No remote SDK config found to merge, error - \(remote?.sdkConfig?.error ?? "NA")")
        }

        return updated
    }

    // MARK: - Cache management
    func cacheSettingsState(settingConfig: SettingsResponse, token: String) {
        if let settingsData = try? JSONEncoder().encode(settingConfig) {
            userDefaults.set(settingsData, forKey: SettingsCacheKeys.configuration(for: token))
            userDefaults.set(Date().timeIntervalSince1970, forKey: SettingsCacheKeys.timestamp(for: token))
        } else {
            Logger.warn(message: "Failed to encode SettingsResponse for caching")
        }
    }

    func getCachedSettingsState(token: String) -> SettingsResponse {
        let key = SettingsCacheKeys.configuration(for: token)

        if let data = userDefaults.data(forKey: key) {
            if let settings = try? JSONDecoder().decode(SettingsResponse.self, from: data) {
                Logger.info(message: "Using cached SettingsResponse, \(settings)")
                return settings
            } else {
                Logger.warn(message: "Failed to decode cached SettingsResponse, using default")
            }
        } else {
            Logger.info(message: "No cached remote settings found, using default")
        }
        return SettingsResponse.default
    }
}
