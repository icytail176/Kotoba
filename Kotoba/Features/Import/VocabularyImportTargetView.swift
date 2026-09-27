//
//  VocabularyImportTargetView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import SwiftUI

struct VocabularyImportTargetView: View {
    @ObservedObject var viewModel: VocabularyImportViewModel
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                Text("选择导入目标")
                    .font(.title2.weight(.semibold))

                Text("CSV 中的重复词会按目标词书单独判断。")
                    .foregroundStyle(.secondary)
                Text("导入至少需要 expression、reading、meaningChinese 3 个必填列；其余标准列可选，未知额外列会忽略。Kotoba 导出始终使用标准 8 列格式。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("导入方式", selection: $viewModel.targetMode) {
                ForEach(VocabularyImportTargetMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch viewModel.targetMode {
                case .newWordBook:
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("词书名称", text: $viewModel.newWordBookName)
                            .textFieldStyle(.roundedBorder)

                        TextField("词书说明（可选）", text: $viewModel.newWordBookDescription)
                            .textFieldStyle(.roundedBorder)
                    }
                case .existingWordBook:
                    if viewModel.availableWordBooks.isEmpty {
                        Text("当前没有可导入的已有词书。")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("目标词书", selection: $viewModel.existingWordBookID) {
                            ForEach(viewModel.availableWordBooks, id: \.id) { wordBook in
                                Text(wordBook.name).tag(wordBook.id.uuidString)
                            }
                        }
                    }
                }
            }

                    }
                    .padding(24)
                }

            Divider()
            HStack {
                Spacer()

                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("继续预览", action: onConfirm)
                    .disabled(!viewModel.canConfirmTarget)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(.bar)
        }
        .frame(minWidth: 360, idealWidth: 460, maxWidth: 560, minHeight: 300, idealHeight: 420, maxHeight: 600)
    }
}

#Preview {
    VocabularyImportTargetView(
        viewModel: VocabularyImportViewModel(),
        onCancel: {},
        onConfirm: {}
    )
}
