import Foundation
import UIKit

/// What an app is actually allowed to do on someone else's iPhone.
///
/// iOS gives an app no accessibility tree for other apps and no way to drive them, so there is no
/// equivalent of the Mac's read-choose-act loop. Everything here goes out through a URL: the
/// Shortcuts app for anything the user has automated, and schemes for the rest.
struct PhoneAction: Decodable, Equatable {
    enum Kind: String, Decodable, CaseIterable { case shortcut, app, search, call, message, maps, web, none }
    let kind: Kind
    /// Shortcut name, app name, search words, phone number, address, or link.
    let value: String
    /// Input for a shortcut, or the body of a message.
    let text: String?
    /// One line to show the person.
    let say: String

    /// Apps that publish a URL scheme. Anything not listed falls back to a web search.
    static let schemes: [String: String] = [
        "safari": "https://", "maps": "maps://", "music": "music://", "apple music": "music://",
        "mail": "message://", "messages": "sms:", "phone": "tel:", "facetime": "facetime://",
        "notes": "mobilenotes://", "reminders": "x-apple-reminderkit://", "calendar": "calshow://",
        "photos": "photos-redirect://", "settings": "App-prefs://", "shortcuts": "shortcuts://",
        "spotify": "spotify://", "youtube": "youtube://", "whatsapp": "whatsapp://",
        "slack": "slack://", "gmail": "googlegmail://", "chrome": "googlechrome://",
        "maps google": "comgooglemaps://", "google maps": "comgooglemaps://", "x": "twitter://",
        "twitter": "twitter://", "instagram": "instagram://", "telegram": "tg://", "zoom": "zoomus://"
    ]

    var url: URL? {
        func escaped(_ raw: String) -> String {
            raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? raw
        }
        switch kind {
        case .shortcut:
            var string = "shortcuts://run-shortcut?name=\(escaped(value))"
            if let text, !text.isEmpty { string += "&input=text&text=\(escaped(text))" }
            return URL(string: string)
        case .app:
            let name = value.lowercased()
            guard let scheme = Self.schemes[name] else {
                return URL(string: "https://www.google.com/search?q=\(escaped(value))")
            }
            return URL(string: scheme.hasSuffix("//") || scheme.hasSuffix(":") ? scheme : scheme + "://")
        case .search:
            return URL(string: "https://www.google.com/search?q=\(escaped(value))")
        case .call:
            return URL(string: "tel:\(value.filter { $0.isNumber || $0 == "+" })")
        case .message:
            let body = text.map { "&body=\(escaped($0))" } ?? ""
            return URL(string: "sms:\(value.filter { $0.isNumber || $0 == "+" })\(body)")
        case .maps:
            return URL(string: "maps://?q=\(escaped(value))")
        case .web:
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
        case .none:
            return nil
        }
    }

    @MainActor
    @discardableResult
    func run() async -> Bool {
        guard let url else { return false }
        return await UIApplication.shared.open(url)
    }
}

enum PhoneActionError: LocalizedError {
    case noKey, invalidResponse, service(status: Int, message: String?)
    var errorDescription: String? {
        switch self {
        case .noKey: return "Add your OpenRouter key in Settings."
        case .invalidResponse: return "The model returned nothing usable. Nothing was opened."
        case .service(let status, let message):
            switch status {
            case 401: return "OpenRouter rejected the key. Check it in Settings."
            case 402: return "OpenRouter reports no credit for this key."
            case 429: return "OpenRouter's rate limit was reached. Try again shortly."
            default: return "OpenRouter returned HTTP \(status). \(message ?? "Nothing was opened.")"
            }
        }
    }
}

enum PhoneBrain {
    static let defaultModel = "inception/mercury-2.5"
    static var model: String { UserDefaults.standard.string(forKey: "PlannerModel") ?? defaultModel }

    /// Shortcut names the person typed in Settings. Without them the model is guessing at names,
    /// because iOS gives no way to read someone's Shortcuts library.
    static var shortcuts: [String] {
        (UserDefaults.standard.string(forKey: "Shortcuts") ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static let schema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "required": ["kind", "value", "text", "say"],
        "properties": [
            "kind": ["type": "string", "enum": PhoneAction.Kind.allCases.map(\.rawValue)],
            "value": ["type": "string"],
            "text": ["type": ["string", "null"]],
            "say": ["type": "string"]
        ]
    ]

    private static var system: String {
        let names = shortcuts.isEmpty ? "none listed" : shortcuts.joined(separator: ", ")
        return """
        You turn one spoken command into a single action an iPhone app is allowed to take. \
        An iPhone app cannot tap around inside other apps; it can only open a URL. Pick the closest of:
        - shortcut: value = the exact name of one of the user's Shortcuts; text = input to pass, or null. \
        Prefer this whenever a listed shortcut matches, because it is the only way to do real work in other apps.
        - app: value = an app name, to open it at its home screen. Nothing more happens inside it.
        - search: value = the words to search the web for.
        - call: value = a phone number.
        - message: value = a phone number; text = the message body. It opens Messages ready to send, unsent.
        - maps: value = a place or address.
        - web: value = a web address.
        - none: nothing can be done; say why in one short sentence.
        The user's Shortcuts: \(names).
        `say` is one short sentence telling the user what you are about to do, in their words. \
        Never invent a shortcut name that is not listed. If the command needs something an iPhone app \
        cannot do, use none and say so plainly.
        """
    }

    static func decide(_ utterance: String) async throws -> PhoneAction {
        guard let key = Keys.read(Keys.openRouter) else { throw PhoneActionError.noKey }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("Lyra", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "max_tokens": 400, "temperature": 0,
            "reasoning": ["enabled": false],
            "messages": [["role": "system", "content": system], ["role": "user", "content": utterance]],
            "response_format": ["type": "json_schema",
                                "json_schema": ["name": "action", "strict": true, "schema": schema]]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PhoneActionError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (object?["error"] as? [String: Any])?["message"] as? String
            throw PhoneActionError.service(status: http.statusCode, message: message?.replacingOccurrences(of: key, with: "[redacted]"))
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (object["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any],
              var content = message["content"] as? String else { throw PhoneActionError.invalidResponse }
        // Some providers fence the JSON despite the schema.
        if let open = content.range(of: "{"), let close = content.range(of: "}", options: .backwards) {
            content = String(content[open.lowerBound...close.lowerBound])
        }
        return try JSONDecoder().decode(PhoneAction.self, from: Data(content.utf8))
    }
}
