//
//  ContentView.swift
//  cove
//
//  Created by Harikrishna C on 22/07/26.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        ShelfView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ShelfItem.self, inMemory: true)
        .environment(\.aiServices, .mock)
}
