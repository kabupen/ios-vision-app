//
//  SettingView.swift
//  ios-vision-app
//
//  Created by Kosuke Takeda on 2025/05/17.
//

import Foundation
import SwiftUI

struct SettingView: View {
    var body: some View {
        NavigationView {
            List {
                NavigationLink(destination: Text("モデル設定画面")){
                    Text("モデル設定")
                }
                NavigationLink(destination: Text("Application info")){
                    Text("App info")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
