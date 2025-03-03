//
//  ColorPaletteSelectorView.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 13/11/2022.
//  Copyright © 2022 Ranchero Software. All rights reserved.
//

import SwiftUI

struct ColorPaletteSelectorView: View {
    
	@StateObject private var appDefaults = AppDefaults.shared
	
	var body: some View {
		HStack {
			appLightButton()
			Spacer()
			appDarkButton()
			Spacer()
			appAutomaticButton()
		}
    }
	
	func appLightButton() -> some View {
		VStack(spacing: 4) {
			Image("app.appearance.light")
				.resizable()
				.aspectRatio(contentMode: .fit)
				.frame(width: 40.0, height: 40.0)
			Text("label.text.use-light-appearance", comment: "Always Light")
				.font(.subheadline)
			if AppDefaults.userInterfaceColorPalette == .light {
				Image(systemName: "checkmark.circle.fill")
					.foregroundColor(Color(uiColor: AppAssets.primaryAccentColor))
			} else {
				Image(systemName: "circle")
			}
		}.onTapGesture {
			AppDefaults.userInterfaceColorPalette = .light
		}
	}
	
	func appDarkButton() -> some View {
		VStack(spacing: 4) {
			Image("app.appearance.dark")
				.resizable()
				.aspectRatio(contentMode: .fit)
				.frame(width: 40.0, height: 40.0)
			Text("label.text.use-dark-appearance", comment: "Always Dark")
				.font(.subheadline)
			if AppDefaults.userInterfaceColorPalette == .dark {
				Image(systemName: "checkmark.circle.fill")
					.foregroundColor(Color(uiColor: AppAssets.primaryAccentColor))
			} else {
				Image(systemName: "circle")
			}
		}.onTapGesture {
			AppDefaults.userInterfaceColorPalette = .dark
		}
	}
	
	func appAutomaticButton() -> some View {
		VStack(spacing: 4) {
			Image("app.appearance.automatic")
				.resizable()
				.aspectRatio(contentMode: .fit)
				.frame(width: 40.0, height: 40.0)
			Text("label.text.use-device-appearance", comment: "Use Device")
				.font(.subheadline)
			if AppDefaults.userInterfaceColorPalette == .automatic {
				Image(systemName: "checkmark.circle.fill")
					.foregroundColor(Color(uiColor: AppAssets.primaryAccentColor))
			} else {
				Image(systemName: "circle")
			}
		}.onTapGesture {
			AppDefaults.userInterfaceColorPalette = .automatic
		}
	}
}

struct DisplayModeView_Previews: PreviewProvider {
    static var previews: some View {
        ColorPaletteSelectorView()
    }
}
