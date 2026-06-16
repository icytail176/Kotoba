//
//  SettingsView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.dailyNewWordLimitKey) private var dailyNewWordLimit = AppSettings.defaultDailyNewWordLimit
    @AppStorage(AppSettings.japaneseSpeechRateKey) private var japaneseSpeechRate = AppSettings.defaultJapaneseSpeechRate
    @AppStorage(AppSettings.autoSpeakWordKey) private var autoSpeakWord = AppSettings.defaultAutoSpeakWord
    @AppStorage(AppSettings.autoSpeakExampleKey) private var autoSpeakExample = AppSettings.defaultAutoSpeakExample
    @AppStorage(AppSettings.randomizeStudyQueueKey) private var randomizeStudyQueue = AppSettings.defaultRandomizeStudyQueue
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        PageScaffold(title: "设置", subtitle: "调整 Kotoba 的本地学习偏好。") {
            Form {
                Section("学习") {
                    Stepper(value: dailyNewWordLimitBinding, in: AppSettings.minimumDailyNewWordLimit...AppSettings.maximumDailyNewWordLimit) {
                        LabeledContent("每日新词数量") {
                            Text("\(dailyNewWordLimitBinding.wrappedValue)")
                                .monospacedDigit()
                        }
                    }

                    Toggle("学习队列随机排列", isOn: $randomizeStudyQueue)

                    LabeledContent("最大复习周期") {
                        Text("\(AppSettings.maximumReviewIntervalDays) 天")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("朗读") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("日语朗读速度") {
                            Text(speechRateText)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: japaneseSpeechRateBinding,
                            in: AppSettings.minimumJapaneseSpeechRate...AppSettings.maximumJapaneseSpeechRate
                        ) {
                            Text("日语朗读速度")
                        } minimumValueLabel: {
                            Text("慢")
                        } maximumValueLabel: {
                            Text("快")
                        }
                    }

                    Toggle("自动朗读单词", isOn: $autoSpeakWord)
                    Toggle("自动朗读例句", isOn: $autoSpeakExample)
                }

                Section("数据") {
                    Button {
                        viewModel.prepareExport(context: modelContext)
                    } label: {
                        Label("导出词书为 CSV", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        viewModel.requestClearAllData()
                    } label: {
                        Label("清空全部数据", systemImage: "trash")
                    }
                }
            }
            .formStyle(.grouped)
            .padding(24)
        }
        .fileExporter(
            isPresented: $viewModel.isExporterPresented,
            document: viewModel.exportDocument,
            contentType: UTType(filenameExtension: "csv") ?? .plainText,
            defaultFilename: "kotoba_vocabulary.csv"
        ) { result in
            viewModel.handleExportCompletion(result)
        }
        .alert(
            "确认清空全部数据？",
            isPresented: $viewModel.isFirstClearConfirmationPresented
        ) {
            Button("取消", role: .cancel) {}
            Button("继续确认", role: .destructive) {
                viewModel.continueToFinalClearConfirmation()
            }
        } message: {
            Text("这会删除全部单词、学习进度和复习记录。下一步仍需输入确认文字后才会执行。")
        }
        .sheet(isPresented: $viewModel.isFinalClearConfirmationPresented) {
            ClearAllDataConfirmationSheet(
                confirmationText: $viewModel.clearConfirmationText,
                requiredPhrase: SettingsViewModel.clearAllDataConfirmationPhrase,
                canConfirm: viewModel.canClearAllData,
                onCancel: {
                    viewModel.cancelFinalClearConfirmation()
                },
                onConfirm: {
                    viewModel.clearAllData(context: modelContext)
                }
            )
        }
        .alert(
            "设置操作失败",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button("好") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert(
            "操作完成",
            isPresented: Binding(
                get: { viewModel.successMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.successMessage = nil
                    }
                }
            )
        ) {
            Button("好") {
                viewModel.successMessage = nil
            }
        } message: {
            Text(viewModel.successMessage ?? "")
        }
    }

    private var dailyNewWordLimitBinding: Binding<Int> {
        Binding {
            AppSettings.clampedDailyNewWordLimit(dailyNewWordLimit)
        } set: { newValue in
            dailyNewWordLimit = AppSettings.clampedDailyNewWordLimit(newValue)
        }
    }

    private var japaneseSpeechRateBinding: Binding<Double> {
        Binding {
            AppSettings.clampedJapaneseSpeechRate(japaneseSpeechRate)
        } set: { newValue in
            japaneseSpeechRate = AppSettings.clampedJapaneseSpeechRate(newValue)
        }
    }

    private var speechRateText: String {
        "\(Int((japaneseSpeechRateBinding.wrappedValue / AppSettings.defaultJapaneseSpeechRate * 100).rounded()))%"
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewModelContainer.make())
        .frame(width: 700, height: 500)
}

private struct ClearAllDataConfirmationSheet: View {
    @Binding var confirmationText: String
    let requiredPhrase: String
    let canConfirm: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("二次确认")
                    .font(.title3.weight(.semibold))

                Text("请输入“\(requiredPhrase)”以确认清空全部本地数据。此操作不可撤销。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("确认文字", text: $confirmationText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()

                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("清空全部数据", role: .destructive, action: onConfirm)
                    .disabled(!canConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
