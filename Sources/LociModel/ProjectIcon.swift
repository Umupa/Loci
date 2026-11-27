import Foundation

/// The curated monochrome SF Symbols a project may wear, kept short and visually even from 16pt up to the
/// large preview on a new project's stage.
public enum ProjectIcon {
  public struct Entry: Hashable, Sendable {
    public let symbol: String
    public let keywords: [String]

    public init(_ symbol: String, keywords: [String]) {
      self.symbol = symbol
      self.keywords = keywords
    }
  }

  public static let fallback = "folder"

  public static let catalog: [Entry] = [
    Entry(
      "chart.line.uptrend.xyaxis",
      keywords: [
        "投资", "基金", "股票", "纳指", "理财", "行情", "资产", "持仓", "etf", "stock", "fund", "invest", "finance",
        "trade", "market",
      ]),
    Entry("chart.pie", keywords: ["预算", "配置", "账目", "统计", "财报", "budget", "portfolio", "analytics"]),
    Entry("creditcard", keywords: ["账单", "消费", "报销", "信用卡", "还贷", "房贷", "expense", "bill", "credit", "payment"]),
    Entry("building.2", keywords: ["公司", "工作", "团队", "事业", "商业", "职场", "company", "work", "business", "career"]),
    Entry(
      "book.closed", keywords: ["精读", "读书", "阅读", "书", "专著", "文献", "论文", "book", "paper", "read", "study"]),
    Entry("terminal", keywords: ["infra", "运维", "命令行", "cli", "终端", "shell", "server", "deploy", "linux", "devops"]),
    Entry("cpu", keywords: ["ai", "大模型", "llm", "模型", "芯片", "算力", "硬件", "gpu", "cpu", "ml", "agent"]),
    Entry(
      "chevron.left.forwardslash.chevron.right",
      keywords: ["代码", "开发", "编程", "源码", "仓库", "前端", "后端", "swift", "rust", "code", "dev", "repo"]),
    Entry("hammer", keywords: ["构建", "打造", "重构", "工坊", "build", "craft", "make"]),
    Entry("wrench.and.screwdriver", keywords: ["调试", "维修", "修理", "折腾", "搭建", "setup", "fix", "debug", "repair"]),
    Entry("doc.text", keywords: ["文档", "笔记", "整理", "简历", "方案", "报告", "doc", "note", "resume", "spec", "report"]),
    Entry("newspaper", keywords: ["新闻", "资讯", "快讯", "周报", "日报", "追踪", "news", "digest", "feed", "newsletter"]),
    Entry("pencil.and.outline", keywords: ["写作", "创作", "文章", "博客", "日记", "随笔", "write", "draft", "blog", "essay"]),
    Entry("graduationcap", keywords: ["面试", "学习", "课程", "考试", "备考", "毕业", "考研", "exam", "interview", "course"]),
    Entry("calendar", keywords: ["日程", "排期", "时间", "预约", "活动", "schedule", "calendar", "event"]),
    Entry("checklist", keywords: ["待办", "清单", "准备", "事项", "任务", "todo", "task", "checklist"]),
    Entry("target", keywords: ["目标", "冲刺", "复盘", "规划", "okr", "goal", "plan", "sprint", "review"]),
    Entry("lightbulb", keywords: ["想法", "灵感", "点子", "调研", "探索", "idea", "research", "brainstorm"]),
    Entry("bookmark", keywords: ["收藏", "书签", "参考", "存档", "bookmark", "archive", "saved"]),
    Entry(
      "airplane",
      keywords: ["旅行", "旅游", "五日", "行程", "机票", "签证", "出差", "东京", "日本", "trip", "travel", "flight", "tour"]),
    Entry("house", keywords: ["搬家", "租房", "买房", "装修", "家", "家居", "房租", "home", "house", "move", "rent", "family"]),
    Entry("cart", keywords: ["购物", "采购", "买", "装备", "shop", "buy", "cart", "gear"]),
    Entry("fork.knife", keywords: ["美食", "做饭", "菜谱", "餐厅", "饮食", "cook", "food", "recipe", "dinner"]),
    Entry("cup.and.saucer", keywords: ["咖啡", "茶", "休息", "日常", "daily", "coffee", "tea"]),
    Entry("car", keywords: ["车", "买车", "自驾", "驾照", "通勤", "car", "drive"]),
    Entry("heart", keywords: ["健康", "体检", "医疗", "睡眠", "心理", "health", "care", "medical"]),
    Entry("figure.run", keywords: ["运动", "健身", "跑步", "减脂", "锻炼", "马拉松", "run", "fitness", "sport", "workout"]),
    Entry("headphones", keywords: ["播客", "音频", "音乐", "歌", "听书", "podcast", "music", "audio"]),
    Entry("camera", keywords: ["摄影", "拍照", "视频", "剪辑", "vlog", "photo", "camera", "video"]),
    Entry("leaf", keywords: ["自然", "植物", "养花", "露营", "环保", "plant", "nature", "camp", "green"]),
    Entry("globe", keywords: ["语言", "英语", "日语", "网页", "出海", "世界", "language", "english", "web", "world"]),
    Entry("folder", keywords: []),
  ]

  public static var symbols: [String] { catalog.map(\.symbol) }

  public static func isValid(_ symbol: String) -> Bool {
    catalog.contains { $0.symbol == symbol }
  }

  /// Picks the closest symbol in `catalog` for `name`, falling back to `folder` when nothing matches.
  public static func inferred(from name: String) -> String {
    let lowered = name.lowercased()
    guard !lowered.isEmpty else { return fallback }
    return catalog.first { entry in entry.keywords.contains { lowered.contains($0) } }?.symbol ?? fallback
  }
}
