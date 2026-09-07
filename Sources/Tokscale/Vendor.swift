import SwiftUI

/// Who actually built the model, worked out from the model id.
///
/// Pointedly *not* tokscale's `provider` field, which records the route rather
/// than the maker. On this machine that field files the same
/// `deepseek-v4-flash` under three different names depending on how it was
/// reached (`deepseek`, `opencode`, `opencode_go`), puts Zhipu's `glm-5.2`
/// under `alibaba_token_plan_cn` because of the plan it billed to, splits
/// `claude-sonnet-4-6` between `anthropic` and `github_copilot`, and calls
/// every locally-run model `lmstudio` whoever wrote it. Grouping by it scatters
/// one vendor across several rows and credits models to companies that had
/// nothing to do with them.
enum Vendor: String, CaseIterable, Codable, Equatable {
    case anthropic
    case openai
    case google
    case deepseek
    case alibaba
    case zhipu
    case moonshot
    case minimax
    case xai
    case xiaomi
    case nvidia
    case meta
    case mistral
    case other

    /// Longest-token-first so `deepseek-v4` cannot be caught by a shorter rule,
    /// and so `gpt-oss` lands on OpenAI rather than on a stray `oss`.
    static func inferred(fromModelID id: String) -> Vendor {
        let name = id.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { name.contains($0) } }

        if has("claude")                          { return .anthropic }
        if has("gpt-", "gpt4", "o1-", "o3-", "o4-", "codex", "davinci", "text-embedding-ada") { return .openai }
        if has("gemini", "gemma", "palm", "bison") { return .google }
        if has("deepseek")                        { return .deepseek }
        if has("qwen", "qwopus", "tongyi")        { return .alibaba }
        if has("glm", "chatglm", "codegeex")      { return .zhipu }
        if has("kimi", "moonshot")                { return .moonshot }
        if has("minimax", "abab")                 { return .minimax }
        if has("grok")                            { return .xai }
        if has("mimo")                            { return .xiaomi }
        if has("nemotron", "nvidia")              { return .nvidia }
        if has("llama", "codellama")              { return .meta }
        if has("mistral", "mixtral", "magistral", "codestral") { return .mistral }
        return .other
    }

    /// What to call this vendor.
    ///
    /// Most of these are brand names and stay as they are in every language —
    /// nobody translates "Anthropic". The ones that go through the strings file
    /// are those with a genuine local name a reader would expect: 通义千问 in
    /// Chinese where the rest of the world writes Qwen.
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai:    return "OpenAI"
        case .google:    return "Google"
        case .deepseek:  return "DeepSeek"
        case .minimax:   return "MiniMax"
        case .xai:       return "xAI"
        case .nvidia:    return "NVIDIA"
        case .meta:      return "Meta"
        case .mistral:   return "Mistral"
        case .alibaba:   return language.t("vendor.name.alibaba")
        case .zhipu:     return language.t("vendor.name.zhipu")
        case .moonshot:  return language.t("vendor.name.moonshot")
        case .xiaomi:    return language.t("vendor.name.xiaomi")
        case .other:     return language.t("vendor.name.other")
        }
    }

    /// The vendor's own mark where the brand has one everybody recognises,
    /// otherwise a neutral tone. Never the intensity palette: a vendor ring
    /// answers "how much of my usage is this company", which is not a level of
    /// anything and must not be read as one.
    var tint: Color {
        switch self {
        case .anthropic: return Color(hex: 0xD97757)
        case .openai:    return Color(hex: 0x10A37F)
        case .google:    return Color(hex: 0x4285F4)
        case .deepseek:  return Color(hex: 0x4D6BFE)
        case .alibaba:   return Color(hex: 0x615CED)
        case .zhipu:     return Color(hex: 0x3859FF)
        case .moonshot:  return Color(hex: 0x1A1A1A)
        case .minimax:   return Color(hex: 0xEC4899)
        case .xai:       return Color(hex: 0xBFBFBF)
        case .xiaomi:    return Color(hex: 0xFF6900)
        case .nvidia:    return Color(hex: 0x76B900)
        case .meta:      return Color(hex: 0x0866FF)
        case .mistral:   return Color(hex: 0xFA520F)
        case .other:     return Palette.textSecondary
        }
    }

    /// Moonshot's mark is near-black, which is invisible on the notch. Only
    /// this one needs lifting, so it is handled rather than the palette being
    /// bent for everybody.
    var ringTint: Color { self == .moonshot ? Color(hex: 0xE8E8E8) : tint }

    /// The company's own mark, where there is one to draw. Vendors without a
    /// published single-path logo fall back to initials — a wrong logo is worse
    /// than honest letters.
    var outline: [[CGPoint]]? {
        switch self {
        case .anthropic: return VendorOutline.anthropic
        case .openai:    return VendorOutline.openai
        case .google:    return VendorOutline.google
        case .deepseek:  return VendorOutline.deepseek
        case .alibaba:   return VendorOutline.qwen
        case .minimax:   return VendorOutline.minimax
        case .nvidia:    return VendorOutline.nvidia
        case .xiaomi:    return VendorOutline.xiaomi
        case .meta:      return VendorOutline.meta
        case .mistral:   return VendorOutline.mistral
        case .zhipu, .moonshot, .xai, .other: return nil
        }
    }
}
