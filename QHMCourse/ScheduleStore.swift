import SwiftUI
import UIKit

/// 全局状态：登录 / 学期 / 课表
@MainActor
final class ScheduleStore: ObservableObject {
    enum Phase {
        case loading          // 启动时检查会话
        case needsLogin       // 未登录，显示登录页
        case ready            // 已登录
    }

    @Published var phase: Phase = .loading
    @Published var errorMessage: String?
    @Published var semesters: [Semester] = []
    @Published var selectedSemester: String = ""
    @Published var selectedWeek: Int? = nil   // nil = 全部周
    @Published var schedule: Schedule?
    @Published var captchaImage: UIImage?
    @Published var username: String = ""
    @Published var isLoggingIn = false

    var loginFailedMessage: String?

    func bootstrap() async {
        phase = .loading
        do {
            if try await EduAPI.shared.isLoggedIn() {
                try await loadSemesters()
                try await loadSchedule(force: false)
                phase = .ready
            } else {
                phase = .needsLogin
            }
        } catch {
            phase = .needsLogin
        }
    }

    // MARK: - 登录

    func refreshCaptcha() async {
        errorMessage = nil
        do {
            captchaImage = try await EduAPI.shared.prepareCaptcha()
            if captchaImage == nil {
                // 会话其实还有效
                try await loadSemesters()
                try await loadSchedule(force: false)
                phase = .ready
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func login(password: String, captcha: String) async {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        defer { isLoggingIn = false }
        do {
            try await EduAPI.shared.login(username: username, password: password, captcha: captcha)
            try await loadSemesters()
            try await loadSchedule(force: true)
            phase = .ready
        } catch {
            loginFailedMessage = error.localizedDescription
            // 验证码已失效，换一张
            captchaImage = nil
            await refreshCaptcha()
        }
    }

    // MARK: - 数据

    func loadSemesters() async throws {
        let list = try await EduAPI.shared.fetchSemesters()
        semesters = list
        if !list.isEmpty {
            let current = list.first { $0.id == selectedSemester } ?? list[0]
            selectedSemester = current.id
        }
    }

    func loadSchedule(force: Bool) async throws {
        let sched = try await EduAPI.shared.fetchSchedule(
            semester: selectedSemester, force: force)
        schedule = sched
        // 周次范围变化时修正选中周
        if let w = selectedWeek, w > sched.maxWeek {
            selectedWeek = nil
        }
    }

    func refresh() async {
        do {
            try await loadSchedule(force: true)
            errorMessage = nil
        } catch EduAPIError.notLoggedIn {
            phase = .needsLogin
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectSemester(_ id: String) async {
        guard id != selectedSemester else { return }
        selectedSemester = id
        selectedWeek = nil
        do {
            try await loadSchedule(force: false)
        } catch EduAPIError.notLoggedIn {
            phase = .needsLogin
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 今天是本学期第几周（用于“本周”按钮）
    var currentWeek: Int? {
        guard let s = schedule else { return nil }
        return SemesterCalendar.currentWeek(semester: s.semesterId)
    }
}
