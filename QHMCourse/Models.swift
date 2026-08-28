import Foundation

struct Semester: Identifiable, Hashable {
    let id: String
    let label: String
}

/// 一个时间段：星期几 + 连续节次
struct Slot: Hashable {
    let day: Int      // 1-7 = 周一..周日
    let units: [Int]  // 节次 1-10，已排序
}

/// 一门课的一次上课安排（同一教室、同一组周次）
struct Activity: Hashable, Identifiable {
    let id = UUID()
    let room: String
    let teachers: [String]
    let weeks: [Int]
    let slots: [Slot]
}

struct Course: Identifiable, Hashable {
    let seqNo: String      // 课程序号，如 38T20003.24
    let name: String
    let code: String       // 课程代码，如 38T20003
    let credit: String
    let teachers: [String]
    let activities: [Activity]
    var id: String { seqNo }
}

struct Schedule {
    let semester: String      // 显示名，如 "2026-2027学年第1学期"
    let semesterId: String    // 教务系统学期 id，如 "322"
    let courses: [Course]

    var maxWeek: Int {
        courses.flatMap { $0.activities }.flatMap { $0.weeks }.max() ?? 20
    }
}

/// 学期起始日期（第一周的周一），用于计算“今天是第几周”
enum SemesterCalendar {
    static let starts: [String: String] = ["322": "2026-08-31"]

    static func startDate(semester: String) -> Date? {
        guard let raw = starts[semester] else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.date(from: raw)
    }

    /// 某学期今天是第几周；未知或不在学期内返回 nil
    static func currentWeek(semester: String) -> Int? {
        guard let start = startDate(semester: semester) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? -1
        guard days >= 0 else { return nil }
        return days / 7 + 1
    }

    /// 第 week 周星期 day (1-7) 的日期；算不出返回 nil
    static func date(semester: String, week: Int, day: Int) -> Date? {
        guard let start = startDate(semester: semester) else { return nil }
        let offset = (week - 1) * 7 + (day - 1)
        return Calendar.current.date(byAdding: .day, value: offset, to: start)
    }
}
