# 民大课表 (iOS)

青海民族大学课程表查询 App（iPhone 版）。

- 登录教务系统（学号 + 密码 + 验证码，密码只在手机内加密后发送给学校服务器）
- 实时抓取课表，格子视图展示（周一~周日 × 10 节课）
- 按周过滤（全部 / 本周 / 第 N 周）、今天高亮、点击课程看详情
- 登录状态自动保存，下次打开无需重新登录

数据来源：青海民族大学教务系统 https://jwxt.qhmu.edu.cn

## 一、发布到 GitHub（用 GitHub Desktop，只需一次）

1. 打开 **GitHub Desktop**（如果还没登录，先登录你的 GitHub 账号）
2. 菜单 **File → Add local repository…**，选择本文件夹 `qhmu-course-ios`
3. 顶部会提示 "Create a repository" / **发布仓库**，点 **Publish repository**（仓库名填 `qhmu-course-ios` 即可，保持 Public 公开）
4. 等它上传完成

## 二、云端自动构建 IPA（每次改动都会自动重跑）

1. 浏览器打开 `github.com/你的用户名/qhmu-course-ios`
2. 点顶部 **Actions** 标签页 → 看到 "Build IPA" 在跑，等它变绿 ✓（约 5-10 分钟）
3. 点进这次绿色的运行 → 页面底部 **Artifacts** 区域 → 下载 **QHMCourse.ipa**

以后每次改完代码，只要在 GitHub Desktop 里 **Commit → Push**，Actions 会自动重新构建。

## 三、安装到 iPhone

把下载的 `QHMCourse.ipa` 用你平时装 IPA 的方式安装即可（如 AltStore / SideStore / TrollStore / 爱思助手等）。

> 首次打开如果提示"未受信任的开发者"，到 iPhone 的 **设置 → 通用 → VPN与设备管理** 里信任一下即可。

## 四、常见问题

- **IPA 只有 30 天下载期限**：GitHub 会自动删掉旧构建产物，重新跑一次 Actions 或重新下载即可。
- **改了代码想更新 App**：改文件 → GitHub Desktop 提交推送 → Actions 重新构建 → 下载新 IPA 覆盖安装。
- **登录提示验证码错误**：点一下验证码图片刷新再输；密码是教务系统（统一身份认证）密码。
- **课表里没有第一周的课**：学校数据第一周（8月31日起）是报到周，课程从第 2 周开始，属正常。

## 目录结构

```
QHMCourse/
  Models.swift           数据模型（学期/课程/周次计算）
  EduAPI.swift           教务系统网络层（CAS 登录 + 课表抓取解析）
  ScheduleStore.swift    界面状态管理
  LoginView.swift        登录页
  ScheduleGridView.swift 课表格子视图
  CourseDetailView.swift 课程详情弹窗
  ContentView.swift      主界面
  QHMUCourseApp.swift    App 入口
project.yml              XcodeGen 配置（云端用它生成 Xcode 工程）
.github/workflows/build.yml   GitHub Actions 构建脚本
```
