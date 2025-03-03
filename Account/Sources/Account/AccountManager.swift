//
//  AccountManager.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 7/18/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import RSCore
import RSWeb
import Articles
import ArticlesDatabase
import RSDatabase

// Main thread only.

@MainActor public final class AccountManager: UnreadCountProvider {

	public static var shared: AccountManager!
	public static let netNewsWireNewsURL = "https://netnewswire.blog/feed.xml"
	private static let jsonNetNewsWireNewsURL = "https://netnewswire.blog/feed.json"

	public let defaultAccount: Account

	private let accountsFolder: String
    private var accountsDictionary = [String: Account]()

	private let defaultAccountFolderName = "OnMyMac"
	private let defaultAccountIdentifier = "OnMyMac"

	public var isSuspended = false
	public var isUnreadCountsInitialized: Bool {
		for account in activeAccounts {
			if !account.isUnreadCountsInitialized {
				return false
			}
		}
		return true
	}
	
	public var unreadCount = 0 {
		didSet {
			if unreadCount != oldValue {
				postUnreadCountDidChangeNotification()
			}
		}
	}

	public var accounts: [Account] {
		return Array(accountsDictionary.values)
	}

	public var sortedAccounts: [Account] {
		return sortByName(accounts)
	}

	public var activeAccounts: [Account] {
		assert(Thread.isMainThread)
		return Array(accountsDictionary.values.filter { $0.isActive })
	}

	public var sortedActiveAccounts: [Account] {
		return sortByName(activeAccounts)
	}
	
	public var lastArticleFetchEndTime: Date? {
		var lastArticleFetchEndTime: Date? = nil
		for account in activeAccounts {
			if let accountLastArticleFetchEndTime = account.metadata.lastArticleFetchEndTime {
				if lastArticleFetchEndTime == nil || lastArticleFetchEndTime! < accountLastArticleFetchEndTime {
					lastArticleFetchEndTime = accountLastArticleFetchEndTime
				}
			} else {
				lastArticleFetchEndTime = nil
				break
			}
		}
		return lastArticleFetchEndTime
	}

	public func existingActiveAccount(forDisplayName displayName: String) -> Account? {
		return AccountManager.shared.activeAccounts.first(where: { $0.nameForDisplay == displayName })
	}
	
	public var refreshInProgress: Bool {
		for account in activeAccounts {
			if account.refreshInProgress {
				return true
			}
		}
		return false
	}
	
	public var combinedRefreshProgress: CombinedRefreshProgress {
		let downloadProgressArray = activeAccounts.map { $0.refreshProgress }
		return CombinedRefreshProgress(downloadProgressArray: downloadProgressArray)
	}
	
	public init(accountsFolder: String) {
		self.accountsFolder = accountsFolder
		
		// The local "On My Mac" account must always exist, even if it's empty.
		let localAccountFolder = (accountsFolder as NSString).appendingPathComponent("OnMyMac")
		do {
			try FileManager.default.createDirectory(atPath: localAccountFolder, withIntermediateDirectories: true, attributes: nil)
		}
		catch {
			assertionFailure("Could not create folder for OnMyMac account.")
			abort()
		}

		defaultAccount = Account(dataFolder: localAccountFolder, type: .onMyMac, accountID: defaultAccountIdentifier)
        accountsDictionary[defaultAccount.accountID] = defaultAccount

		readAccountsFromDisk()

		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidInitialize(_:)), name: .UnreadCountDidInitialize, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(accountStateDidChange(_:)), name: .AccountStateDidChange, object: nil)

		DispatchQueue.main.async {
			self.updateUnreadCount()
		}
	}

	// MARK: - API
	
	public func createAccount(type: AccountType) -> Account {
		let accountID = type == .cloudKit ? "iCloud" : UUID().uuidString
		let accountFolder = (accountsFolder as NSString).appendingPathComponent("\(type.rawValue)_\(accountID)")

		do {
			try FileManager.default.createDirectory(atPath: accountFolder, withIntermediateDirectories: true, attributes: nil)
		} catch {
			assertionFailure("Could not create folder for \(accountID) account.")
			abort()
		}
		
		let account = Account(dataFolder: accountFolder, type: type, accountID: accountID)
		accountsDictionary[accountID] = account
		
		var userInfo = [String: Any]()
		userInfo[Account.UserInfoKey.account] = account
		NotificationCenter.default.post(name: .UserDidAddAccount, object: self, userInfo: userInfo)
		
		return account
	}
	
    @MainActor public func deleteAccount(_ account: Account) {
		guard !account.refreshInProgress else {
			return
		}
		
		account.prepareForDeletion()
		
		accountsDictionary.removeValue(forKey: account.accountID)
		account.isDeleted = true
		
		do {
			try FileManager.default.removeItem(atPath: account.dataFolder)
		}
		catch {
			assertionFailure("Could not create folder for OnMyMac account.")
			abort()
		}
		
		updateUnreadCount()

		var userInfo = [String: Any]()
		userInfo[Account.UserInfoKey.account] = account
		NotificationCenter.default.post(name: .UserDidDeleteAccount, object: self, userInfo: userInfo)
	}
	
	public func duplicateServiceAccount(type: AccountType, username: String?) -> Bool {
		guard type != .onMyMac else {
			return false
		}
		for account in accounts {
			if account.type == type && username == account.username {
				return true
			}
		}
		return false
	}
	
	public func existingAccount(with accountID: String) -> Account? {
		return accountsDictionary[accountID]
	}
	
	public func existingContainer(with containerID: ContainerIdentifier) -> Container? {
		switch containerID {
		case .account(let accountID):
			return existingAccount(with: accountID)
		case .folder(let accountID, let folderName):
			return existingAccount(with: accountID)?.existingFolder(with: folderName)
		default:
			break
		}
		return nil
	}
	
	public func existingFeed(with itemID: ItemIdentifier) -> FeedProtocol? {
		switch itemID {
		case .folder(let accountID, let folderName):
			if let account = existingAccount(with: accountID) {
				return account.existingFolder(with: folderName)
			}
		case .feed(let accountID, let feedID):
			if let account = existingAccount(with: accountID) {
				return account.existingFeed(withFeedID: feedID)
			}
		default:
			break
		}
		return nil
	}
	
	public func suspendNetworkAll() {
		isSuspended = true
        for account in accounts {
            account.suspendNetwork()
        }
	}

	public func suspendDatabaseAll() {
        for account in accounts {
            account.suspendDatabase()
        }
	}

	public func resumeAll() {
		isSuspended = false
        for account in accounts {
            account.resumeDatabaseAndDelegate()
        }
        for account in accounts {
            account.resume()
        }
	}

	public func receiveRemoteNotification(userInfo: [AnyHashable : Any]) async {
        for account in activeAccounts {
			await account.receiveRemoteNotification(userInfo: userInfo)
		}
	}

	public func refreshAll(errorHandler: @escaping @MainActor (Error) -> Void) async {

		guard let reachability = try? Reachability(hostname: "apple.com"), reachability.connection != .unavailable else { return }

		await withTaskGroup(of: Void.self) { group in
			for account in activeAccounts {
				group.addTask {
					do {
						try await account.refreshAll()
					} catch {
						Task { @MainActor in
							errorHandler(error)
						}
					}
				}
			}
			await group.waitForAll()
		}
	}
	
	public func sendArticleStatusAll(completion: (() -> Void)? = nil) {
		let group = DispatchGroup()

		for account in activeAccounts {
			group.enter()

			Task { @MainActor in
				try? await account.sendArticleStatus()
				group.leave()
			}
		}

		group.notify(queue: DispatchQueue.global(qos: .background)) {
			completion?()
		}
	}


	public func syncArticleStatusAll() async {

		await withTaskGroup(of: Void.self) { group in
			for account in activeAccounts {
				group.addTask {
					try? await account.syncArticleStatus()
				}
			}
			
			await group.waitForAll()
		}
	}
	
	public func saveAll() {
        for account in accounts {
            account.save()
        }
	}
	
	public func anyAccountHasAtLeastOneFeed() -> Bool {
		for account in activeAccounts {
			if account.hasAtLeastOneFeed() {
				return true
			}
		}

		return false
	}
	
	public func anyAccountHasNetNewsWireNewsSubscription() -> Bool {
		return anyAccountHasFeedWithURL(Self.netNewsWireNewsURL) || anyAccountHasFeedWithURL(Self.jsonNetNewsWireNewsURL)
	}

	public func anyAccountHasFeedWithURL(_ urlString: String) -> Bool {
		for account in activeAccounts {
			if let _ = account.existingFeed(withURL: urlString) {
				return true
			}
		}
		return false
	}

    public func anyLocalOriCloudAccountHasAtLeastOneTwitterFeed() -> Bool {
        // We removed our Twitter code, and the ability to read feeds from Twitter,
        // when Twitter announced the end of the free tier for the Twitter API.
        // We are cheering on Twitter’s increasing irrelevancy.
        
        for account in accounts {
            if account.type == .cloudKit || account.type == .onMyMac {
                for feed in account.flattenedFeeds() {
                    if let components = URLComponents(string: feed.url), let host = components.host {
                        if host == "twitter.com" { // Allow, for instance, blog.twitter.com, which might have an actual RSS feed
                            return true
                        }
                    }
                }
            }
        }
        
        return false
    }

    public func anyLocalOriCloudAccountHasAtLeastOneRedditAPIFeed() -> Bool {
        // We removed our Reddit code, and the ability to read feeds from Reddit,
        // when Reddit announced the end of the free tier for the Reddit API.
        // We are cheering on Reddit’s increasing irrelevancy.

        for account in accounts {
            if account.type == .cloudKit || account.type == .onMyMac {
                for feed in account.flattenedFeeds() {
                    if feedRequiresRedditAPI(feed) {
                        return true
                    }
                }
            }
        }

        return false
    }

    /// Return true if a feed is for reddit.com and the path doesn’t end with .rss.
    ///
    /// More info: [Pathogen-David's Guide to RSS and Reddit!](https://www.reddit.com/r/pathogendavid/comments/tv8m9/pathogendavids_guide_to_rss_and_reddit/)
    private func feedRequiresRedditAPI(_ feed: Feed) -> Bool {
        if let components = URLComponents(string: feed.url), let host = components.host {
            return host.hasSuffix("reddit.com") && !components.path.hasSuffix(".rss")
        }
        return false
    }

	// MARK: - Fetching Articles

	// These fetch articles from active accounts and return a merged Set<Article>.

    @MainActor public func asyncFetchArticles(_ fetchType: FetchType) async throws -> Set<Article> {

        guard activeAccounts.count > 0 else {
            return Set<Article>()
        }

        let articles = try await withThrowingTaskGroup(of: Set<Article>.self) { taskGroup in
            for account in activeAccounts {
                taskGroup.addTask {
                    let articles = try await account.asyncFetchArticles(fetchType)
                    return articles
                }
            }

            var allFetchedArticles = Set<Article>()
            for try await oneAccountArticles in taskGroup {
                allFetchedArticles.formUnion(oneAccountArticles)
            }

            return allFetchedArticles
        }

        return articles
    }



    @MainActor public func fetchArticles(_ fetchType: FetchType) throws -> Set<Article> {
		precondition(Thread.isMainThread)

		var articles = Set<Article>()
		for account in activeAccounts {
			articles.formUnion(try account.fetchArticles(fetchType))
		}
		return articles
	}

	public func fetchArticlesAsync(_ fetchType: FetchType, _ completion: @escaping ArticleSetResultBlock) {
        precondition(Thread.isMainThread)
        
        guard activeAccounts.count > 0 else {
            completion(.success(Set<Article>()))
            return
        }
        
        var allFetchedArticles = Set<Article>()
        var databaseError: DatabaseError?
        let dispatchGroup = DispatchGroup()
        
        for account in activeAccounts {
            
            dispatchGroup.enter()
            
            account.fetchArticlesAsync(fetchType) { (articleSetResult) in
                precondition(Thread.isMainThread)
                
                switch articleSetResult {
                case .success(let articles):
                    allFetchedArticles.formUnion(articles)
                case .failure(let error):
                    databaseError = error
                }
                
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            if let databaseError {
                completion(.failure(databaseError))
            }
            else {
                completion(.success(allFetchedArticles))
            }
        }
    }

	public func fetchUnreadArticlesBetween(limit: Int? = nil, before: Date? = nil, after: Date? = nil) throws -> Set<Article> {
		precondition(Thread.isMainThread)

		var articles = Set<Article>()
		for account in activeAccounts {
			articles.formUnion(try account.fetchUnreadArticlesBetween(limit: limit, before: before, after: after))
		}
		return articles
	}
    
    // MARK: - Fetching Article Counts
    
    public func fetchCountForStarredArticles() throws -> Int {
        precondition(Thread.isMainThread)
        var count = 0
        for account in activeAccounts {
            count += try account.fetchCountForStarredArticles()
        }
        return count
    }

	// MARK: - Caches

	/// Empty caches that can reasonably be emptied — when the app moves to the background, for instance.
	public func emptyCaches() {
		for account in accounts {
			account.emptyCaches()
		}
	}

	// MARK: - Notifications
	
	@MainActor @objc func unreadCountDidInitialize(_ notification: Notification) {
		guard let _ = notification.object as? Account else {
			return
		}
		if isUnreadCountsInitialized {
			postUnreadCountDidInitializeNotification()
		}
	}
	
	@MainActor @objc func unreadCountDidChange(_ notification: Notification) {
		guard let _ = notification.object as? Account else {
			return
		}
		updateUnreadCount()
	}
	
    @MainActor @objc func accountStateDidChange(_ notification: Notification) {
		updateUnreadCount()
	}
}

// MARK: - Private

private extension AccountManager {

    @MainActor func updateUnreadCount() {
		unreadCount = calculateUnreadCount(activeAccounts)
	}

	func loadAccount(_ accountSpecifier: AccountSpecifier) -> Account? {
		return Account(dataFolder: accountSpecifier.folderPath, type: accountSpecifier.type, accountID: accountSpecifier.identifier)
	}

	func loadAccount(_ filename: String) -> Account? {
		let folderPath = (accountsFolder as NSString).appendingPathComponent(filename)
		if let accountSpecifier = AccountSpecifier(folderPath: folderPath) {
			return loadAccount(accountSpecifier)
		}
		return nil
	}

	func readAccountsFromDisk() {
		var filenames: [String]?

		do {
			filenames = try FileManager.default.contentsOfDirectory(atPath: accountsFolder)
		}
		catch {
			print("Error reading Accounts folder: \(error)")
			return
		}
		
        if let sortedFilenames = filenames?.sorted() {
            for oneFilename in sortedFilenames {
                guard oneFilename != defaultAccountFolderName else {
                    continue
                }
                if let oneAccount = loadAccount(oneFilename) {
                    if !duplicateServiceAccount(oneAccount) {
                        accountsDictionary[oneAccount.accountID] = oneAccount
                    }
                }
            }
        }
	}
	
	func duplicateServiceAccount(_ account: Account) -> Bool {
		return duplicateServiceAccount(type: account.type, username: account.username)
	}

	func sortByName(_ accounts: [Account]) -> [Account] {
		// LocalAccount is first.
		
		return accounts.sorted { (account1, account2) -> Bool in
			if account1 === defaultAccount {
				return true
			}
			if account2 === defaultAccount {
				return false
			}
			return (account1.nameForDisplay as NSString).localizedStandardCompare(account2.nameForDisplay) == .orderedAscending
		}
	}
}

private struct AccountSpecifier {

	let type: AccountType
	let identifier: String
	let folderPath: String
	let folderName: String
	let dataFilePath: String


	init?(folderPath: String) {
		if !FileManager.default.isFolder(atPath: folderPath) {
			return nil
		}
		
		let name = NSString(string: folderPath).lastPathComponent
		if name.hasPrefix(".") {
			return nil
		}
		
		let nameComponents = name.components(separatedBy: "_")
		
		guard nameComponents.count == 2, let rawType = Int(nameComponents[0]), let accountType = AccountType(rawValue: rawType) else {
			return nil
		}

		self.folderPath = folderPath
		self.folderName = name
		self.type = accountType
		self.identifier = nameComponents[1]

		self.dataFilePath = AccountSpecifier.accountFilePathWithFolder(self.folderPath)
	}

	private static let accountDataFileName = "AccountData.plist"

	private static func accountFilePathWithFolder(_ folderPath: String) -> String {
		return NSString(string: folderPath).appendingPathComponent(accountDataFileName)
	}
}
