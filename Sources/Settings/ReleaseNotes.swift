import Foundation

/// What one release changed, in the app's own words.
struct ReleaseNote: Equatable {
    /// Matched against `CFBundleShortVersionString`, so it has to be exactly
    /// the string `MARKETING_VERSION` is set to.
    let version: String
    /// One line under the title. What this release is *about*.
    let headline: String
    let changes: [Change]

    /// A title carries the change; the detail is optional, so a small fix can
    /// be a single line rather than a line padded out to match its neighbours.
    struct Change: Equatable {
        let title: String
        let detail: String

        init(title: String, detail: String = "") {
            self.title = title
            self.detail = detail
        }
    }
}

/// The release history the app ships with.
enum ReleaseNotes {
    static let all: [ReleaseNote] = [
        ReleaseNote(
            version: "1.0.0",
            headline: "把 tokscale 搬进刘海 — 三个环，随时一瞥",
            changes: [
                ReleaseNote.Change(
                    title: "今日 · 本月 · 累计",
                    detail: "三个常驻环，分别是今天、这个月和全部时间用掉的 Token。"
                        + "环下是 Token 数，悬停能看到等效价值、输入输出分布、请求次数和用得最多的模型。"
                ),
                ReleaseNote.Change(
                    title: "环的弧度有明确含义",
                    detail: "今日对比近 30 天最高的一天，本月对比上月同期，累计对比下一个里程碑。"
                        + "每张卡片都会写清楚它在跟什么比 — 弧走到 100% 是你超过了自己，不是警告。"
                ),
                ReleaseNote.Change(
                    title: "按服务商拆分，用到了才出现",
                    detail: "Anthropic、OpenAI、DeepSeek、通义千问… 每家一个环，默认全部关闭，"
                        + "在设置里按需勾选。列表由本机实际用量生成，没用过的厂商不会出现。"
                ),
                ReleaseNote.Change(
                    title: "模型归属按模型名判断",
                    detail: "同一个模型走不同渠道调用会被合并成一行，本地跑的 Qwen 仍然算通义千问 — "
                        + "不再因为计费渠道把 GLM 记到别家名下。"
                ),
                ReleaseNote.Change(
                    title: "订阅回本",
                    detail: "在设置里填入某家的月费和续费日，它的卡片就会显示这个计费周期内产生的等效 "
                        + "API 价值是订阅费的多少倍、还差多少或已超出多少。按真实计费周期算，"
                        + "不是按自然月 — 3 号扣费的套餐，付的就是 3 号到下月 2 号。"
                ),
                ReleaseNote.Change(
                    title: "装好即用，无需任何配置",
                    detail: "tokscale 已内置在 App 内（MIT 协议），不需要 Homebrew、npm 或 node。"
                        + "全程本地：不碰钥匙串、不弹密码框、不上传任何数据。"
                )
            ]
        )
    ]

    static func note(for version: String) -> ReleaseNote? {
        all.first { $0.version == version }
    }

    /// The note worth showing on this launch, if there is one.
    static func unseen(in version: String,
                       lastSeen: String?,
                       notes: [ReleaseNote] = ReleaseNotes.all) -> ReleaseNote? {
        guard lastSeen != version else { return nil }
        return notes.first { $0.version == version }
    }
}
