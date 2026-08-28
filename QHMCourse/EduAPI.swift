import Foundation
import Security
import UIKit

enum EduAPIError: Error, LocalizedError {
    case notLoggedIn
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "登录已过期"
        case .network(let s): return "网络错误: \(s)"
        case .server(let s): return s
        }
    }
}

/// 青海民族大学教务系统 (URP/eams + CAS) 客户端
final class EduAPI {
    static let shared = EduAPI()
    static let base = "https://jwxt.qhmu.edu.cn"
    static let cas = "https://cas.qhmu.edu.cn"

    let session: URLSession
    private var loginURL: String = ""
    private var execution: String = ""
    private var cache: [String: Schedule] = [:]

    private init() {
        // 默认配置使用共享 Cookie 存储，iOS 会自动跨启动保留会话
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: - 工具

    private func firstMatch(_ text: String, pattern: String, group: Int = 1) -> String? {
        guard let m = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            .firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
            m.numberOfRanges > group,
            let r = Range(m.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    private func allMatches(_ text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    private func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
         .replacingOccurrences(of: "&nbsp;", with: "")
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 表单值编码。不能用 URLComponents：它不转义 + 号，服务器会把密文里的 + 当空格，导致解密失败
    private func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// 实时数据的 GET：一律忽略本地缓存。教务系统全是实时状态，
    /// 缓存的旧验证码图/旧页面会导致“刷不出来”“没数据”这类怪问题
    private func liveRequest(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        return req
    }

    private func fetchText(_ url: URL) async throws -> (status: Int, html: String) {
        do {
            let (data, resp) = try await session.data(for: liveRequest(url))
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return (status, String(data: data, encoding: .utf8) ?? "")
        } catch {
            throw EduAPIError.network(error.localizedDescription)
        }
    }

    // MARK: - 登录

    func isLoggedIn() async throws -> Bool {
        guard let url = URL(string: Self.base + "/eams/courseTableForStd.action") else { return false }
        let (_, html) = try await fetchText(url)
        return html.contains("semesterCalendar")
    }

    /// 发起登录流程并下载验证码；已登录返回 nil
    func prepareCaptcha() async throws -> UIImage? {
        guard let url = URL(string: Self.base + "/eams/homeExt.action") else {
            throw EduAPIError.network("无效地址")
        }
        let (data, resp) = try await session.data(for: liveRequest(url))
        let html = String(data: data, encoding: .utf8) ?? ""
        guard let exec = firstMatch(html, pattern: #"name="execution" value="([^"]+)""#) else {
            return nil  // 没跳登录页 => 会话仍有效
        }
        execution = exec
        loginURL = resp.url?.absoluteString ?? ""
        guard let capURL = URL(string: Self.cas + "/cas/captcha.jpg") else {
            throw EduAPIError.network("无效地址")
        }
        let (imgData, _) = try await session.data(for: liveRequest(capURL))
        guard let img = UIImage(data: imgData) else {
            // 服务器没给图（可能返回了错误页），报出来而不是假装没登录
            throw EduAPIError.server("验证码图片加载失败，点图片重试")
        }
        return img
    }

    /// 执行 CAS 登录。成功返回；失败抛错（错误信息取自页面提示）
    func login(username: String, password: String, captcha: String) async throws {
        guard !execution.isEmpty else { throw EduAPIError.server("请先刷新验证码") }

        let form: [(String, String)] = [
            ("username", username),
            ("password", try await rsaEncrypt(password)),
            ("captcha", captcha),
            ("execution", execution),
            ("_eventId", "submit"),
            ("rememberMe", "true"),
            ("fpVisitorId", ""), ("mfaState", ""), ("geolocation", ""),
            ("drcomUsername", ""), ("trustAgent", ""), ("qrCodeKey", ""), ("currentMenu", ""),
        ]

        var req = URLRequest(url: URL(string: loginURL)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form
            .map { formEncode($0.0) + "=" + formEncode($0.1) }
            .joined(separator: "&")
            .data(using: .utf8)

        // 跟随重定向：成功会一路跳到教务首页；失败停在登录页（仍含 execution）
        let (data, _) = try await session.data(for: req)
        let html = String(data: data, encoding: .utf8) ?? ""
        if let newExec = firstMatch(html, pattern: #"name="execution" value="([^"]+)""#) {
            execution = newExec
            throw EduAPIError.server(extractLoginError(html))
        }
        execution = ""
    }

    private func rsaEncrypt(_ password: String) async throws -> String {
        guard let url = URL(string: Self.cas + "/cas/jwt/publicKey") else {
            throw EduAPIError.network("无效地址")
        }
        let (data, _) = try await session.data(for: liveRequest(url))
        let pem = String(data: data, encoding: .utf8) ?? ""
        let b64 = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard let keyData = Data(base64Encoded: b64),
              let secKey = SecKeyCreateWithData(keyData as CFData, [
                  kSecAttrKeyType: kSecAttrKeyTypeRSA,
                  kSecAttrKeyClass: kSecAttrKeyClassPublic,
              ] as CFDictionary, nil) else {
            throw EduAPIError.server("RSA 公钥解析失败")
        }
        var error: Unmanaged<CFError>?
        guard let enc = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1,
                                                  Data(password.utf8) as CFData, &error) as Data? else {
            throw EduAPIError.server("密码加密失败")
        }
        // 关键：CAS 登录页 JS 要求密文带 __RSA__ 前缀
        return "__RSA__" + enc.base64EncodedString()
    }

    private func extractLoginError(_ html: String) -> String {
        // 1) 页面上的 el-alert 提示（服务器渲染的可读文案）
        for m in allMatches(html, pattern: #"<el-alert[^>]*title="([^"]+)""#) where m.count > 1 {
            let text = m[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(100)) }
        }
        // 2) JS 里的 errors 数组，如 ["账号或密码错误。"]
        for m in allMatches(html, pattern: #"var\s+errors\s*=\s*\[(.*?)\];"#) where m.count > 1 {
            var texts: [String] = []
            for s in allMatches(m[1], pattern: #""([^"]*)""#) where s.count > 1 && !s[1].isEmpty {
                texts.append(decodeUnicodeEscapes(s[1]))
            }
            if !texts.isEmpty {
                return String(texts.joined(separator: " ").prefix(100))
            }
        }
        return "登录失败，请检查账号、密码和验证码"
    }

    /// 把 "账号" 这类 JS 转义还原成中文
    private func decodeUnicodeEscapes(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\\", s.distance(from: i, to: s.endIndex) >= 6,
               s[s.index(after: i)] == "u",
               let end = s.index(i, offsetBy: 6, limitedBy: s.endIndex),
               let code = UInt32(s[s.index(i, offsetBy: 2)..<end], radix: 16),
               let scalar = UnicodeScalar(code) {
                out.append(Character(scalar))
                i = end
            } else {
                out.append(s[i])
                i = s.index(after: i)
            }
        }
        return out
    }

    // MARK: - 学期列表

    func fetchSemesters() async throws -> [Semester] {
        let shell = try await fetchShell()
        let tagId = firstMatch(shell, pattern: #"id="(semesterBar\d+Semester)""#)
            ?? "semesterBar20826294511Semester"
        var req = URLRequest(url: URL(string: Self.base + "/eams/dataQuery.action")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let fields: [(String, String)] = [
            ("tagId", tagId),
            ("dataType", "semesterCalendar"),
            ("value", ""),
            ("empty", "false"),
        ]
        req.httpBody = fields
            .map { formEncode($0.0) + "=" + formEncode($0.1) }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await session.data(for: req)
        let text = String(data: data, encoding: .utf8) ?? ""
        // 响应是 JS 对象字面量: semesters:{y0:[{id:322,schoolYear:"2026-2027",name:"1"},...]}
        var items: [(id: Int, label: String)] = []
        for m in allMatches(text, pattern: #"\{id:(\d+),schoolYear:"([^"]+)",name:"([^"]+)"\}"#) {
            if m.count == 4, let id = Int(m[1]) {
                items.append((id, "\(m[2])学年第\(m[3])学期"))
            }
        }
        items.sort { $0.id > $1.id }
        return items.map { Semester(id: String($0.id), label: $0.label) }
    }

    // MARK: - 课表

    private func fetchShell() async throws -> String {
        guard let url = URL(string: Self.base + "/eams/courseTableForStd.action") else {
            throw EduAPIError.network("无效地址")
        }
        let (_, html) = try await fetchText(url)
        guard html.contains("semesterCalendar") else { throw EduAPIError.notLoggedIn }
        return html
    }

    func fetchSchedule(semester: String, force: Bool = false) async throws -> Schedule {
        if !force, let cached = cache[semester] { return cached }

        let shell = try await fetchShell()
        // 学号 ids：页面 searchTable() 里注入的必传参数，缺了服务器查不到课表
        // 注意：正则必须写在 ##"..."## 里——在 #"..."# 里 \\( 会变成两个反斜杠，
        // 正则含义就从"字面量 ("变成"反斜杠+("，永远匹配不上
        var ids = firstMatch(shell, pattern: ##"addInput\(form,\s*"ids",\s*"(\d+)"\)"##) ?? ""
        if ids.isEmpty { ids = firstMatch(shell, pattern: #"ids=(\d+)"#) ?? "" }
        var sem = semester
        if sem.isEmpty {
            sem = firstMatch(shell, pattern: ##"semesterCalendar\(\{[^}]*value:"(\d+)"##) ?? ""
        }

        // 壳响应会下发 semester.id Cookie，课表接口必须带着它：
        // 实测带 Cookie 跨连接 8/8 成功，缺 Cookie 必 500（id to load is required）。
        // 这个 Cookie 名带点号，部分 iOS 版本会漏存，这里手动补一份保险
        let cookieProps: [HTTPCookiePropertyKey: Any] = [
            .name: "semester.id",
            .value: sem.isEmpty ? "322" : sem,
            .domain: "jwxt.qhmu.edu.cn",
            .path: "/eams",
        ]
        if let c = HTTPCookie(properties: cookieProps) {
            HTTPCookieStorage.shared.setCookie(c)
        }

        // 直接字符串拼 URL（不能用 URLComponents：它会把路径里的 ! 编码成 %21，服务器就认不出了）
        let urlStr = Self.base + "/eams/courseTableForStd!courseTable.action"
            + "?setting.kind=std&ids=\(ids)&semester.id=\(sem)&startWeek="
        guard let url = URL(string: urlStr) else {
            throw EduAPIError.network("无效地址")
        }

        // 服务器每次响应后都强制断开连接，课表接口又挑剔：
        // 失败就整轮重试（重新刷壳 -> 再抓课表），最多 3 轮
        var html: String?
        var lastStatus = 0
        var lastPage = ""
        for _ in 1...3 {
            let (status, page) = try await fetchText(url)
            lastStatus = status
            lastPage = page
            if page.contains("new TaskActivity(") {
                html = page
                break
            }
            if page.contains(#"name="execution""#) {
                throw EduAPIError.notLoggedIn  // 被踢回 CAS 登录页
            }
            _ = try? await fetchShell()
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        guard let html = html else {
            // 拿到的是错误页：带出 HTTP 状态和服务器错误原因，方便定位
            let reason = firstMatch(lastPage, pattern: #"错误原因[:：]\s*([^<]*)"#)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var msg = "没拿到课程数据（HTTP \(lastStatus)"
            if !reason.isEmpty { msg += "，\(String(reason.prefix(80)))" }
            else { msg += "，返回页面 \(lastPage.count) 字符" }
            msg += "），请稍后重试"
            throw EduAPIError.server(msg)
        }

        var semesterLabel = ""
        if let s = (try? await fetchSemesters())?.first(where: { $0.id == sem }) {
            semesterLabel = s.label
        }
        let schedule = parseSchedule(html: html, semester: semesterLabel, semesterId: sem)
        cache[semester] = schedule
        return schedule
    }

    // MARK: - 解析

    /// 页面里嵌了两块数据：课程列表表格 + JS 的 TaskActivity 调用
    private func parseSchedule(html: String, semester: String, semesterId: String) -> Schedule {
        // 1. 课程列表: 序号|代码|名称|学分|课程序号|教师|备注|操作 -> seqNo -> (code, credit, teachers)
        var meta: [String: (code: String, credit: String, teachers: String)] = [:]
        for m in allMatches(html, pattern: #"<tr>(.*?)</tr>"#) {
            let row = m.count > 1 ? m[1] : ""
            let cells = allMatches(row, pattern: #"<td[^>]*>(.*?)</td>"#).compactMap { c in
                c.count > 1 ? stripTags(c[1]) : nil
            }
            if cells.count >= 8, Int(cells[0]) != nil {
                meta[cells[4]] = (cells[1], cells[3], cells[5])
            }
        }

        // 2. TaskActivity 块: 按 "var teachers =" 切块（变量在调用之前，不能按 new TaskActivity 切）
        var activitiesBySeq: [String: [Activity]] = [:]
        var nameBySeq: [String: String] = [:]
        let ns = html as NSString
        let splitter = try! NSRegularExpression(pattern: #"var\s+teachers\s*="#)
        let splits = splitter.matches(in: html, range: NSRange(location: 0, length: ns.length))
        for i in 0..<splits.count {
            let start = splits[i].range.location + splits[i].range.length
            let end = i + 1 < splits.count ? splits[i + 1].range.location : ns.length
            let block = ns.substring(with: NSRange(location: start, length: end - start))

            guard let name = firstMatch(block, pattern: #"courseName\s*\+=\s*"([^"]*)""#) else { continue }
            // 任课教师：只取 {id:数字,name:"xx"}，避开 title:{name:"职称"}
            var teachers: [String] = []
            let actTeachers = firstMatch(block, pattern: #"var\s+actTeachers\s*=\s*\[(.*?)\];"#) ?? ""
            for t in allMatches(actTeachers, pattern: #"\{id:\d+\s*,\s*name:"([^"]+)""#) where t.count > 1 {
                teachers.append(t[1])
            }

            guard let call = firstMatch(block, pattern: ##"new\s+TaskActivity\((.*?)\)\s*;"##) else { continue }
            let seqNo = firstMatch(call, pattern: ##""(\d+)\(([^)]+)\)""##, group: 2) ?? ""
            let roomWeek = allMatches(call, pattern: #""(\d+)"\s*,\s*"([^"]+)"\s*,\s*"([01]{10,})""#).first
            let room = roomWeek.flatMap { $0.count > 2 ? $0[2] : nil } ?? ""
            let weeksStr = roomWeek.flatMap { $0.count > 3 ? $0[3] : nil } ?? ""
            // 位图第 0 位是占位符，第 1 位 = 第 1 周（实测 startWeek=1 就包含第 1 周课程）
            let weeks: [Int] = weeksStr.enumerated().compactMap { i, ch in ch == "1" ? i : nil }

            // 格子定位: index = 天*unitCount + 节次
            var byDay: [Int: [Int]] = [:]
            for s in allMatches(block, pattern: #"index\s*=\s*(\d+)\s*\*\s*unitCount\s*\+\s*(\d+)\s*;"#) where s.count > 2 {
                if let day = Int(s[1]), let unit = Int(s[2]) {
                    byDay[day + 1, default: []].append(unit + 1)
                }
            }
            guard !byDay.isEmpty else { continue }
            let slots = byDay.map { Slot(day: $0.key, units: $0.value.sorted()) }
                .sorted { $0.day < $1.day }
            nameBySeq[seqNo] = name
            activitiesBySeq[seqNo, default: []].append(
                Activity(room: room, teachers: teachers, weeks: weeks, slots: slots))
        }

        // 3. 合并成课程
        var courses: [Course] = []
        for (seqNo, acts) in activitiesBySeq {
            let m = meta[seqNo]
            let code = m?.code ?? String(seqNo.prefix { $0 != "." })
            let credit = m?.credit ?? ""
            var teachers = m?.teachers.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty } ?? []
            if teachers.isEmpty {
                for a in acts where !a.teachers.isEmpty {
                    teachers = a.teachers
                    break
                }
            }
            courses.append(Course(
                seqNo: seqNo,
                name: nameBySeq[seqNo] ?? seqNo,
                code: code,
                credit: credit,
                teachers: teachers,
                activities: acts))
        }
        courses.sort { $0.name < $1.name }
        return Schedule(semester: semester, semesterId: semesterId, courses: courses)
    }
}
