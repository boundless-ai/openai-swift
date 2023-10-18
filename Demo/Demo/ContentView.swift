//
//  ContentView.swift
//  Demo
//
//  Created by nate parrott on 2/23/23.
//

import SwiftUI
import OpenAI

struct ContentView: View {
    @State private var prompt = "what is internet explorer"
    @State private var text: String = ""
    @AppStorage("key") private var key = ""

    var body: some View {
        Form {
            Section {
                TextField("API key", text: $key)
                TextField("Prompt to complete", text: $prompt, onCommit: complete)
                Button("Complete Text", action: complete)
                Button("Complete Chat", action: completeChat)
            }
            if text != "" {
                Section {
                    Text(text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                }
            }
        }
    }

    private func complete() {
        if key == "" { return }
    }

    private func completeChat() {
        if key == "" { return }
        let messages: [OpenAI.Message] = [
            .init(role: .system, content: "You are a helpful assistant. Answer in one sentence if possible."),
            .init(role: .user, content: prompt)
        ]

        let openAI = OpenAI(apiKey: key)
        let stream = try! openAI.completeChatStreaming(.init(messages: messages), apiURL: URL(string: "http://127.0.0.1:5000/chat_completion")!)
        Task {
            do {
                for try await response in stream {
                    text = response.content
                }
            } catch let error {
                print(error)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
