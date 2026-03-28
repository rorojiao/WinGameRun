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

/// GPTK (D3DMetal) 自动安装视图
struct GPTKGuideView: View {
    enum InstallState {
        case detecting
        case alreadyInstalled(String?)
        case downloading
        case installing
        case installed
        case failed(String)
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

            case .downloading:
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("setup.gptk.downloading")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

            case .installing:
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("setup.gptk.installing")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

            case .installed:
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .resizable()
                        .foregroundStyle(.green)
                        .frame(width: 80, height: 80)
                    Text("setup.gptk.installed")
                        .font(.headline)
                }

            case .failed(let error):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .resizable()
                        .foregroundStyle(.yellow)
                        .frame(width: 60, height: 60)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            Spacer()
            HStack {
                if case .failed = state {
                    Button("setup.gptk.skip") {
                        showSetup = false
                    }
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("setup.retry") {
                        startInstallation()
                    }
                    .keyboardShortcut(.defaultAction)
                } else if case .alreadyInstalled = state {
                    Spacer()
                    Button("setup.done") {
                        showSetup = false
                    }
                    .keyboardShortcut(.defaultAction)
                } else if case .installed = state {
                    Spacer()
                    Button("setup.done") {
                        showSetup = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 400, height: 250)
        .onAppear {
            startInstallation()
        }
    }

    private func startInstallation() {
        state = .detecting
        Task {
            if D3DMetal.isAvailable() {
                await MainActor.run {
                    state = .alreadyInstalled(D3DMetal.detectedVersion())
                }
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run { showSetup = false }
                return
            }

            await MainActor.run { state = .downloading }
            do {
                try await D3DMetal.autoInstall()
                await MainActor.run { state = .installed }
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run { showSetup = false }
            } catch {
                await MainActor.run {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }
}

#Preview {
    GPTKGuideView(path: .constant([]), showSetup: .constant(true))
}
