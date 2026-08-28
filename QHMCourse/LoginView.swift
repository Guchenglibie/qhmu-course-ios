import SwiftUI
import UIKit

/// 教务系统登录页（CAS：学号 + 密码 + 验证码）
struct LoginView: View {
    @EnvironmentObject var store: ScheduleStore
    @State private var password = ""
    @State private var captcha = ""
    @FocusState private var focused: Field?

    enum Field { case username, password, captcha }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    fields
                    if let err = store.loginFailedMessage {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let err = store.errorMessage {
                        // 验证码加载失败等错误也会显示出来，不再无限转圈
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    loginButton
                    tip
                }
                .padding(24)
            }
            .navigationTitle("登录教务系统")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if store.captchaImage == nil {
                    await store.refreshCaptcha()
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 44))
                .foregroundColor(.blue)
            Text("青海民族大学课表")
                .font(.title2.bold())
            Text("登录教务系统后即可实时查询课程表")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }

    private var fields: some View {
        VStack(spacing: 12) {
            TextField("学号", text: $store.username)
                .keyboardType(.numberPad)
                .textContentType(.username)
                .focused($focused, equals: .username)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)

            SecureField("密码", text: $password)
                .textContentType(.password)
                .focused($focused, equals: .password)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)

            HStack(spacing: 12) {
                TextField("验证码", text: $captcha)
                    .keyboardType(.asciiCapable)
                    .focused($focused, equals: .captcha)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .onSubmit { submit() }

                Button {
                    Task { await store.refreshCaptcha() }
                } label: {
                    Group {
                        if let img = store.captchaImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(width: 110, height: 44)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("点击刷新验证码")
            }
        }
    }

    private var loginButton: some View {
        Button {
            submit()
        } label: {
            Group {
                if store.isLoggingIn {
                    ProgressView().progressViewStyle(.circular)
                } else {
                    Text("登 录").font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canSubmit ? Color.blue : Color.gray.opacity(0.4))
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(!canSubmit || store.isLoggingIn)
    }

    private var tip: some View {
        Text("数据来自青海民族大学教务系统 jwxt.qhmu.edu.cn，账号密码仅发送给学校服务器用于登录。")
            .font(.caption2)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
    }

    private var canSubmit: Bool {
        !store.username.isEmpty && !password.isEmpty && !captcha.isEmpty
    }

    private func submit() {
        guard canSubmit, !store.isLoggingIn else { return }
        focused = nil
        let pwd = password
        let cap = captcha
        captcha = ""
        Task { await store.login(password: pwd, captcha: cap) }
    }
}
