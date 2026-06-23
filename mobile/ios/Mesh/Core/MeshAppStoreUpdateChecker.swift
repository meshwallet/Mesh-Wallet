import Combine
import Foundation

enum MeshAppStoreConfig {
  static let appStoreID = "6773052229"

  static var appStoreURL: URL {
    URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
  }
}

struct AppStoreUpdateOffer: Equatable {
  let storeVersion: String
  let appStoreURL: URL
}

private struct AppStoreLookupResponse: Decodable {
  let results: [Result]

  struct Result: Decodable {
    let version: String
    let trackViewUrl: String?
  }
}

@MainActor
final class MeshAppStoreUpdateChecker: ObservableObject {
  @Published private(set) var updateOffer: AppStoreUpdateOffer?
  @Published var showUpdateAlert = false

  private static var didCheckThisLaunch = false
  private var hasPendingUpdatePrompt = false

  func checkOnLaunchIfNeeded() async {
    guard !Self.didCheckThisLaunch else { return }
    Self.didCheckThisLaunch = true

    guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
          !currentVersion.isEmpty
    else { return }

    guard let lookup = await fetchStoreListing() else { return }
    guard Self.isVersion(currentVersion, olderThan: lookup.version) else { return }

    updateOffer = AppStoreUpdateOffer(storeVersion: lookup.version, appStoreURL: lookup.url)
    hasPendingUpdatePrompt = true
  }

  /// Call once splash / Face ID / passcode are finished — alerts do not show over launch chrome.
  func presentUpdateAlertIfReady() {
    guard hasPendingUpdatePrompt, updateOffer != nil else { return }
    guard !showUpdateAlert else { return }
    showUpdateAlert = true
    hasPendingUpdatePrompt = false
  }

  func openAppStore() {
    MeshAppLinks.open(updateOffer?.appStoreURL ?? MeshAppStoreConfig.appStoreURL)
  }

  /// iTunes lookup returns different versions per storefront; US/RU often lag behind GB/DE.
  private static let lookupCountries = [
    "us", "gb", "de", "fr", "au", "ca", "jp", "ru", "kz", "ua", "by",
  ]

  private func fetchStoreListing() async -> (version: String, url: URL)? {
    let countries = Self.lookupCountryCandidates()
    var best: (version: String, url: URL)?

    await withTaskGroup(of: (version: String, url: URL)?.self) { group in
      for country in countries {
        group.addTask {
          await Self.fetchStoreListing(country: country)
        }
      }
      for await listing in group {
        guard let listing else { continue }
        guard let current = best else {
          best = listing
          continue
        }
        if Self.compare(current.version, listing.version) == .orderedAscending {
          best = listing
        }
      }
    }

    return best
  }

  private static func lookupCountryCandidates() -> [String] {
    var countries = lookupCountries
    if let region = Locale.current.region?.identifier.lowercased(),
       !region.isEmpty,
       !countries.contains(region)
    {
      countries.insert(region, at: 0)
    }
    return countries
  }

  private nonisolated static func fetchStoreListing(country: String) async -> (version: String, url: URL)? {
    var components = URLComponents(string: "https://itunes.apple.com/lookup")!
    components.queryItems = [
      URLQueryItem(name: "id", value: MeshAppStoreConfig.appStoreID),
      URLQueryItem(name: "country", value: country),
    ]
    guard let url = components.url else { return nil }

    do {
      var request = URLRequest(url: url)
      request.timeoutInterval = 12
      request.cachePolicy = .reloadIgnoringLocalCacheData
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
        return nil
      }

      let decoded = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
      guard let result = decoded.results.first,
            !result.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return nil }

      let storeURL =
        result.trackViewUrl.flatMap(URL.init(string:))
        ?? MeshAppStoreConfig.appStoreURL
      return (result.version, storeURL)
    } catch {
      return nil
    }
  }

  private static func isVersion(_ installed: String, olderThan store: String) -> Bool {
    compare(installed, store) == .orderedAscending
  }

  private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
    let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
    let count = max(left.count, right.count)
    for index in 0 ..< count {
      let l = index < left.count ? left[index] : 0
      let r = index < right.count ? right[index] : 0
      if l < r { return .orderedAscending }
      if l > r { return .orderedDescending }
    }
    return .orderedSame
  }
}
