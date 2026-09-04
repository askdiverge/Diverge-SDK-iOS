//
//  EntryView.swift
//  Harness
//
//  Created by Daniel Wennberg on 2026-06-26.
//

import SwiftUI
import AIConversation

struct EntryView: View {

    @State private var token = ""
    @State private var chat: AIChat?
    @State private var isChatPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Chat Example")
                    .font(.headline)

                TextField("Session token", text: self.$token)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                Button("Launch chat") {
                    let token = self.token
                    self.chat = AIChat(
                        .init(
                            tokenProvider: {
                                print("start get new token")
                                try await Task.sleep(for: .seconds(2))
                                print("finish get new token")
                                return token
                            },
                            resetConversation: {
                                print("start reset token")
                                try await Task.sleep(for: .seconds(2))
                                print("finish reset token")
                                return token
                            },
                            deleteData: {
                                print("start delete data")
                                try await Task.sleep(for: .seconds(2))
                                print("finish delete data")
                            },
                            onOpenLink: { print("open link:", $0) }
                        )
                    )
                    self.isChatPresented = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.token.isEmpty)
            }
            .padding()
            .navigationDestination(isPresented: self.$isChatPresented) {
                if let chat = self.chat {
                    chat.makeView()
                }
            }
        }
        .frame(minWidth: 390, minHeight: 760)
    }
}
