import SwiftUI

/// 课表格子视图（7 天 × 10 节，支持按周过滤、点击看详情、定位当前课）
struct ScheduleGridView: View {
    @EnvironmentObject var store: ScheduleStore
    @State private var detailCourse: Course?

    private let unitH: CGFloat = 58
    private let timeColW: CGFloat = 36
    private let days = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    private var schedule: Schedule { store.schedule ?? Schedule(semester: "", semesterId: "", courses: []) }

    /// 当前视图里的周数（nil = 全部周）
    private var week: Int? { store.selectedWeek }

    /// 是否在看“本周/全部”且现在还在上课时间（决定是否显示定位按钮、高亮当前节）
    private var showNow: Bool {
        guard let cw = store.currentWeek, week == nil || week == cw else { return false }
        return ClassPeriod.current() != nil
    }

    // MARK: - 布局计算

    struct GridBlock: Identifiable {
        let id = UUID()
        let day: Int
        let unit: Int       // 起始节次 1-10
        let span: Int       // 连续节次数
        let course: Course
        let activity: Activity
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
                                                course: course, activity: act))
                    }
                }
            }
        }
        return merged
    }

    /// 这块是不是“现在正在上”的课（今天 + 当前节次落在它的时间范围内）
    private func isNowBlock(_ b: GridBlock) -> Bool {
        guard showNow, let p = ClassPeriod.current() else { return false }
        let wd = Calendar.current.component(.weekday, from: Date())  // 1=周日...7=周六
        let today = wd == 1 ? 7 : wd - 1
        return b.day == today && b.unit <= p && p < b.unit + b.span
    }

    /// 这一节是不是现在正在上的节次
    private func isNowUnit(_ u: Int) -> Bool {
        showNow && ClassPeriod.current() == u
    }

    // MARK: - 视图

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 8) {
                weekPicker(proxy: proxy)
                dayHeader
                grid
                    .background(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 12)
            .onAppear {
                // 打开课表时自动定位到当前该上的课（等布局稳定再滚）
                guard showNow else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        proxy.scrollTo("nowRow", anchor: .top)
                    }
                }
            }
        }
        .sheet(item: $detailCourse) { course in
            CourseDetailView(course: course, schedule: schedule)
        }
    }

    // MARK: 周次选择

    private func weekPicker(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
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
            if showNow {
                Button {
                    withAnimation(.easeOut(duration: 0.35)) {
                        proxy.scrollTo("nowRow", anchor: .top)
                    }
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.onAccent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("定位到当前节课")
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Color(.secondarySystemBackground))
                .foregroundColor(selected ? Theme.onAccent : .primary)
                .clipShape(Capsule())
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
                        .font(.caption.weight(headerDay(d) ? .bold : .medium))
                        .foregroundColor(d >= 6 ? .secondary : .primary)
                    Text(dateText(d))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(headerDay(d) ? Theme.todayTint : Color.clear)
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
                        BlockView(block: b, isNow: isNowBlock(b))
                            .frame(width: dayW - 4,
                                   height: CGFloat(b.span) * unitH - 4)
                            .position(x: timeColW + CGFloat(b.day - 1) * dayW + dayW / 2,
                                      y: CGFloat(b.unit - 1) * unitH + CGFloat(b.span) * unitH / 2)
                            .onTapGesture { detailCourse = b.course }
                    }
                    // 定位锚点：当前这一节所在行
                    if showNow, let p = ClassPeriod.current() {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .id("nowRow")
                            .position(x: timeColW + 1, y: CGFloat(p - 1) * unitH + unitH / 2)
                    }
                }
                .frame(width: geo.size.width, height: totalH)
            }
        }
        .frame(height: CGFloat(8) * unitH)
    }

    private func gridBackground(dayW: CGFloat, totalH: CGFloat) -> some View {
        Canvas { ctx, size in
            // 当前这一节的整行淡色底
            if showNow, let p = ClassPeriod.current() {
                let rect = CGRect(x: timeColW, y: CGFloat(p - 1) * unitH,
                                  width: size.width - timeColW, height: unitH)
                ctx.fill(Path(rect), with: .color(Theme.nowTint))
            }
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

    /// 时间列：第几节 + 上下课时间；正在上的那一节高亮
    private func timeColumn(totalH: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(1...10, id: \.self) { u in
                VStack(spacing: 1) {
                    Text("\(u)")
                        .font(.system(size: 12, weight: isNowUnit(u) ? .heavy : .semibold))
                        .foregroundColor(isNowUnit(u) ? Theme.accent : .secondary)
                    Text(ClassPeriod.times[u - 1].start)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(ClassPeriod.times[u - 1].end)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(width: timeColW, height: unitH)
            }
        }
        .frame(height: totalH, alignment: .top)
    }
}

// MARK: - 单个课程块

private struct BlockView: View {
    let block: ScheduleGridView.GridBlock
    let isNow: Bool

    /// 本课配色（跟详情页一致）
    private var palette: (background: Color, foreground: Color) {
        Theme.courseColors(for: block.course.seqNo)
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左侧色条，同一门课一眼能认出来
            Rectangle()
                .fill(palette.foreground.opacity(0.55))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.course.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if !block.activity.room.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 8))
                        Text(block.activity.roomShort)
                            .font(.system(size: 10))
                            .lineLimit(2)
                    }
                    .opacity(0.8)
                }
            }
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(palette.background)
        .foregroundColor(palette.foreground)
        .cornerRadius(8)
        .overlay(
            // 现在正在上的课：描边 + 发光
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.accent, lineWidth: isNow ? 2 : 0)
        )
        .shadow(color: isNow ? Theme.accent.opacity(0.4) : .clear,
                radius: isNow ? 6 : 0, y: isNow ? 2 : 0)
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
