import Foundation

public struct SupportTemplatesQuestion: Equatable {
    public var question: String
    public var originalKeys: [String]
    public var normalizedKeys: [String]
    public var value: String

    public init(question: String = "", originalKeys: [String] = [], normalizedKeys: [String] = [], value: String = "") {
        self.question = question
        self.originalKeys = originalKeys
        self.normalizedKeys = normalizedKeys
        self.value = value
    }
}

public struct SupportTemplatesFile: Equatable {
    public var url: String
    // Keyed by the normalized question.
    public var questions: [String: SupportTemplatesQuestion]

    public init(url: String = "", questions: [String: SupportTemplatesQuestion] = [:]) {
        self.url = url
        self.questions = questions
    }

    public var isEmpty: Bool {
        return self.url.isEmpty && self.questions.isEmpty
    }

    var sortedQuestions: [(normalized: String, question: SupportTemplatesQuestion)] {
        return self.questions.sorted(by: { utf16Less($0.key, $1.key) }).map { (normalized: $0.key, question: $0.value) }
    }
}

public func isSupportTemplatesFileName(_ name: String) -> Bool {
    let lowercased = name.lowercased()
    return lowercased.hasPrefix("tl_") && lowercased.hasSuffix(".txt")
}

private enum ReadState {
    case none
    case question
    case keys
    case value
    case url
}

private func token(of line: [UInt16]) -> String? {
    guard line.count >= 3, line.first == 0x7B, line.last == 0x7D else {
        return nil
    }
    let name = line[1 ..< line.count - 1]
    for unit in name {
        if !((unit >= 0x41 && unit <= 0x5A) || unit == 0x5F) {
            return nil
        }
    }
    return stringFromUnits(name)
}

public func parseSupportTemplatesFile(_ data: Data) -> SupportTemplatesFile {
    var result = SupportTemplatesFile()
    var url = ""
    var question = SupportTemplatesQuestion()

    func emit() {
        var value = Array(question.value.utf16)
        while value.last == 0x0A {
            value.removeLast()
        }
        question.value = stringFromUnits(value)
        let normalized = supportTemplatesNormalizedQuestion(question.question)
        if !normalized.isEmpty && result.questions[normalized] == nil {
            result.questions[normalized] = question
        }
        question = SupportTemplatesQuestion()
    }

    var state = ReadState.none
    var hadKeys = false
    var hadValue = false
    for lineBytes in data.split(separator: 0x0A, omittingEmptySubsequences: false) {
        let units = Array(trimmedUnits(Array(String(decoding: lineBytes, as: UTF8.self).utf16)))
        let line = stringFromUnits(units)
        if let token = token(of: units) {
            if state == .value {
                hadKeys = false
                hadValue = false
            }
            let newState: ReadState
            switch token {
            case "VALUE":
                newState = hadValue ? .none : .value
            case "KEYS":
                newState = hadKeys ? .none : .keys
            case "QUESTION":
                newState = .question
            case "URL":
                newState = .url
            default:
                newState = .none
            }
            if state == .value {
                emit()
            }
            state = newState
        } else {
            if !units.isEmpty {
                if state == .value {
                    hadValue = true
                } else if state == .keys {
                    hadKeys = true
                }
            }
            switch state {
            case .keys:
                if !units.isEmpty {
                    question.originalKeys.append(line)
                    let normalized = supportTemplatesNormalizedKey(line)
                    if !normalized.isEmpty {
                        question.normalizedKeys.append(normalized)
                    }
                }
            case .value:
                if !question.value.isEmpty {
                    question.value += "\n"
                }
                question.value += line
            case .question:
                if question.question.isEmpty {
                    question.question = line
                }
            case .url:
                if url.isEmpty {
                    url = line
                }
            case .none:
                break
            }
        }
    }
    emit()
    result.url = url
    return result
}
