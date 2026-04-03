//
//  GPTKGuideView.swift
//  WinGameRun
//
//  This file is part of WinGameRun.
//
//  WinGameRun is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  WinGameRun is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with WinGameRun.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import WinGameKit

/// GPTK (D3DMetal) 安装引导视图
/// D3DMetal 受 Apple EULA 限制不能自动安装，引导用户手动下载 GPTK
struct GPTKGuideView: View {
    enum InstallState {
        case detecting
        case alreadyInstalled(String?)
        case notInstalled
    }

    @State private var state: InstallState = .detecting
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool

    var body: some View {
        VStack {
            Text("setup.gptk.title")
                .font(.title)
                .fontWeight(.bold)
            Text("setup.gptk.subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()

            switch state {
            case .detecting:
                ProgressView()
                    .scaleEffect(2)
                Text("setup.gptk.detecting")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

            case .alreadyInstalled(let version):
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .resizable()
                        .foregroundStyle(.green)
                        .frame(width: 80, height: 80)
                    if let version = version {
                        Text("GPTK \(version)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }

            case .notInstalled:
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .resizable()
                        .foregroundStyle(.blue)
                        .frame(width: 60, height: 60)
                    Text("setup.gptk.notinstalled")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    // 引导用户前往 Apple Developer 下载 GPTK
                    Button("setup.gptk.open.developer") {
                        NSWorkspace.shared.open(
                            URL(string: "https://developer.apple.com/games/")!
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer()
            HStack {
                if case .alreadyInstalled = state {
                    Spacer()
                    Button("setup.done") {
                        showSetup = false
                    }
                    .keyboardShortcut(.defaultAction)
                } else if case .notInstalled = state {
                    Button("setup.gptk.skip") {
                        showSetup = false
                    }
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("setup.gptk.installed.check") {
                        detect()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 400, height: 280)
        .onAppear {
            detect()
        }
    }

    private func detect() {
        state = .detecting
        Task {
            let available = D3DMetal.isAvailable()
            let version = D3DMetal.detectedVersion()
            await MainActor.run {
                if available {
                    state = .alreadyInstalled(version)
                } else {
                    state = .notInstalled
                }
            }
            if available {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run { showSetup = false }
            }
        }
    }
}

#Preview {
    GPTKGuideView(path: .constant([]), showSetup: .constant(true))
}
