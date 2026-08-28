import SwiftUI

/// 课程详情弹窗：名称/代码/学分/教师 + 各次上课安排
struct CourseDetailView: View {
    let course: Course
    let schedule: Schedule
    @Environment(\.presentationMode) var presentation

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if !course.teachers.isEmpty {
                        infoRow(icon: "person.fill", title: "教师",
                                text: course.teachers.joined(separator: "、"))
                    }
                    if !course.code.isEmpty {
                        infoRow(icon: "number", title: "课程代码", text: course.code)
                    }
                    if !course.credit.isEmpty {
                        infoRow(icon: "star.fill", title: "学分", text: course.credit)
                    }
                    activitiesSection
                }
                .padding(20)
            }
            .navigationTitle(course.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { presentation.wrappedValue.dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(course.name)
                    .font(.title3.bold())
                Text("课程序号 \(course.seqNo)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "book.closed.fill")
                .font(.title2)
                .foregroundColor(.blue)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(12)
    }

    private func infoRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("上课安排")
                .font(.headline)
                .padding(.top, 4)
            ForEach(course.activities) { act in
                ActivityRow(activity: act)
            }
        }
    }
}

/// 一条上课安排：时间 / 周次 / 地点
private struct ActivityRow: View {
    let activity: Activity

    private var timeText: String {
        let dayNames = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let parts = activity.slots.map { slot -> String in
            let units = slot.units.sorted()
            let range = units.count == 1
                ? "第\(units[0])节"
                : "第\(units.first!)–\(units.last!)节"
            return "\(dayNames[slot.day])\(range)"
        }
        return parts.joined(separator: "、")
    }

    private var weeksText: String {
        // 2,3,4,5,10,11 -> 第2-5、10-11周
        let ws = activity.weeks.sorted()
        guard !ws.isEmpty else { return "" }
        var parts: [String] = []
        var start = ws[0], prev = ws[0]
        for w in ws.dropFirst() {
            if w == prev + 1 {
                prev = w
            } else {
                parts.append(start == prev ? "\(start)" : "\(start)-\(prev)")
                start = w
                prev = w
            }
        }
        parts.append(start == prev ? "\(start)" : "\(start)-\(prev)")
        return "第" + parts.joined(separator: "、") + "周"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(timeText)
                    .font(.subheadline.weight(.medium))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(weeksText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if !activity.room.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(activity.room)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}
