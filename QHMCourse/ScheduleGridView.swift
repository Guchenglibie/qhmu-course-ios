import SwiftUI

/// 课表格子视图（7 天 × 10 节，支持按周过滤、点击看详情）
struct ScheduleGridView: View {
    @EnvironmentObject var store: ScheduleStore
    @State private var detailCourse: Course?

    private let unitH: CGFloat = 54
    private let timeColW: CGFloat = 26
    private let days = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    private var schedule: Schedule { store.schedule ?? Schedule(semester: "", semesterId: "", courses: []) }

    /// 当前视图里的周数（nil = 全部周）
    private var week: Int? { store.selectedWeek }

    // MARK: - 布局计算

    struct GridBlock: Identifiable {
        let id = UUID()
        let day: Int
        let unit: Int       // 起始节次 1-10
        let span: Int       // 连续节次数
        let course: Course
        let activity: Activity
        let color: Color
    }

    private var blocks: [GridBlock] {
        var merged: [GridBlock] = []
        for course in schedule.courses {
            for act in course.activities {
                guard week == nil || act.weeks.contains(week!) else { continue }
                // 同一天里合并连续节次
                for slot in act.slots {
                    let units = slot.units.sorted()
                    var runs: [(start: Int, span: Int)] = []
                    for u in units {
                        if let last = runs.last, u == last.start + last.span {
                            runs[runs.count - 1].span += 1
                        } else {
                            runs.append((u, 1))
                        }
                    }
                    for run in runs {
                        merged.append(GridBlock(day: slot.day, unit: run.start, span: run.span,
                                                course: course, activity: act,
                                                color: colorFor(course.seqNo)))
                    }
                }
            }
        }
        return merged
    }

    private func colorFor(_ key: String) -> Color {
        var h: UInt64 = 5381
        for b in key.unicodeScalars { h = h &* 33 &+ UInt64(b.value) }
        let hue = Double(h % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.92)
    }

    // MARK: - 视图

    var body: some View {
        VStack(spacing: 8) {
            weekPicker
            dayHeader
            grid
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 10)
        .sheet(item: $detailCourse) { course in
            CourseDetailView(course: course, schedule: schedule)
        }
    }

    // MARK: 周次选择

    private var weekPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", selected: week == nil) { store.selectedWeek = nil }
                if let cw = store.currentWeek {
                    chip("本周", selected: week == cw) { store.selectedWeek = cw }
                }
                ForEach(1...schedule.maxWeek, id: \.self) { w in
                    chip("\(w)", selected: week == w) { store.selectedWeek = w }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.blue : Color(.secondarySystemBackground))
                .foregroundColor(selected ? .white : .primary)
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: 表头

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: timeColW)
            ForEach(1...7, id: \.self) { d in
                VStack(spacing: 2) {
                    Text(days[d - 1])
                        .font(.caption.weight(headerDay(d) ? .bold : .regular))
                    Text(dateText(d))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    headerDay(d)
                        ? Color.blue.opacity(0.12).cornerRadius(8)
                        : Color.clear
                )
            }
        }
    }

    /// 今天高亮：选“全部”或选中的就是本周时，今天的列加蓝底
    private func headerDay(_ d: Int) -> Bool {
        guard let cw = store.currentWeek else { return false }
        let isThisWeek = (week == nil) || (week == cw)
        return isThisWeek && Calendar.current.component(.weekday, from: Date()) == weekdayIndex(d)
    }

    private func weekdayIndex(_ day: Int) -> Int {
        // Calendar weekday: 1=周日 ... 7=周六；我们的 day: 1=周一 ... 7=周日
        day == 7 ? 1 : day + 1
    }

    private func dateText(_ d: Int) -> String {
        let w = week ?? store.currentWeek
        guard let w = w,
              let date = SemesterCalendar.date(semester: schedule.semesterId, week: w, day: d) else {
            return ""
        }
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }

    // MARK: 格子

    private var grid: some View {
        GeometryReader { geo in
            let dayW = (geo.size.width - timeColW) / 7
            let totalH = CGFloat(10) * unitH
            ScrollView(.vertical, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    gridBackground(dayW: dayW, totalH: totalH)
                    timeColumn(totalH: totalH)
                    ForEach(blocks) { b in
                        BlockView(block: b)
                            .frame(width: dayW - 4,
                                   height: CGFloat(b.span) * unitH - 4)
                            .position(x: timeColW + CGFloat(b.day - 1) * dayW + dayW / 2,
                                      y: CGFloat(b.unit - 1) * unitH + CGFloat(b.span) * unitH / 2)
                            .onTapGesture { detailCourse = b.course }
                    }
                }
                .frame(width: geo.size.width, height: totalH)
            }
        }
        .frame(height: CGFloat(8) * unitH)
    }

    private func gridBackground(dayW: CGFloat, totalH: CGFloat) -> some View {
        Canvas { ctx, size in
            var path = Path()
            for d in 0...7 {
                let x = timeColW + CGFloat(d) * dayW
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: totalH))
            }
            for u in 0...10 {
                let y = CGFloat(u) * unitH
                path.move(to: CGPoint(x: timeColW, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(path, with: .color(Color(.systemGray5)), lineWidth: 0.5)
        }
    }

    private func timeColumn(totalH: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(1...10, id: \.self) { u in
                Text("\(u)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: timeColW, height: unitH)
            }
        }
        .frame(height: totalH, alignment: .top)
    }
}

// MARK: - 单个课程块

private struct BlockView: View {
    let block: ScheduleGridView.GridBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(block.course.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(4)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if !block.activity.room.isEmpty {
                Text(block.activity.roomShort)
                    .font(.system(size: 9))
                    .lineLimit(2)
                    .opacity(0.75)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(block.color)
        .cornerRadius(6)
    }
}

extension Activity {
    /// 教室名缩短：取括号前部分（"鸿文J7M(东序校区(东))" -> "鸿文J7M"）
    var roomShort: String {
        if let i = room.firstIndex(of: "(") {
            return String(room[..<i])
        }
        return room
    }
}
