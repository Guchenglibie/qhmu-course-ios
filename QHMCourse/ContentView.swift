import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ScheduleStore

    var body: some View {
        switch store.phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("正在检查登录状态…")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        case .needsLogin:
            LoginView()
        case .ready:
            mainView
        }
    }

    private var mainView: some View {
        VStack(spacing: 10) {
            topBar
            if let err = store.errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            if store.schedule?.courses.isEmpty ?? true {
                emptyState
            } else {
                ScheduleGridView()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Picker("学期", selection: $store.selectedSemester) {
                ForEach(store.semesters) { s in
                    Text(s.label).tag(s.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 180)
            .onChange(of: store.selectedSemester) { newValue in
                Task { await store.selectSemester(newValue) }
            }

            Spacer()

            if let err = store.schedule?.semester, !err.isEmpty {
                Text(shortSemester(err))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("刷新课表")
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    /// "2026-2027学年第1学期" -> "2026-2027-1"
    private func shortSemester(_ label: String) -> String {
        label
            .replacingOccurrences(of: "学年", with: "-")
            .replacingOccurrences(of: "第", with: "")
            .replacingOccurrences(of: "学期", with: "")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("这个学期还没有课程安排")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
