//
//  AIChatApp.swift
//  AIChat
//
//  Created by 박희지 on 7/25/26.
//

import SwiftUI

@main
struct AIChatApp: App {
    var body: some Scene {
        WindowGroup {
            // 인자 없으면 기존과 동일. `-ui-testing` 등은 bootstrap이 store·service만 주입.
            ChatView(viewModel: UITestingBootstrap.makeViewModel())
        }
    }
}
