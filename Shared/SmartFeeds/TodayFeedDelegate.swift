//
//  TodayFeedDelegate.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 11/19/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import Foundation
import RSCore
import Articles
import ArticlesDatabase
import Account

struct TodayFeedDelegate: SmartFeedDelegate {

	var itemID: ItemIdentifier? {
		return ItemIdentifier.smartFeed(String(describing: TodayFeedDelegate.self))
	}
	
	let nameForDisplay = NSLocalizedString("smartfeed.title.today", comment: "Today pseudo-feed title")
	let fetchType = FetchType.today(nil)
	var smallIcon: IconImage? {
		return AppAssets.todayFeedImage
	}
	
	func fetchUnreadCount(for account: Account, completion: @escaping SingleUnreadCountCompletionBlock) {
		account.fetchUnreadCountForToday(completion)
	}
}

