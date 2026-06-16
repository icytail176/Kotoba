//
//  TodayStudyView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI
import SwiftData

struct TodayStudyView: View {
    var body: some View {
        PageScaffold(title: "今日学习", subtitle: "查看今天需要处理的新词和复习任务。") {
            StudyView()
        }
    }
}

#Preview {
    TodayStudyView()
        .modelContainer(PreviewModelContainer.make())
        .frame(width: 700, height: 500)
}
