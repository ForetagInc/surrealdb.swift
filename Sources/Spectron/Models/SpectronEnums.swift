import Foundation

public enum QueryMode: String, Sendable, Codable, CaseIterable {
    case vector
    case bm25
    case hybrid
    case hybridGraph = "hybrid_graph"
}

public enum DocumentStatus: String, Sendable, Codable, CaseIterable {
    case queued
    case extracting
    case chunking
    case embedding
    case rendering
    case transcribing
    case captioning
    case keywording
    case ready
    case failed
}

public enum IngestProfile: String, Sendable, Codable, CaseIterable {
    case textOnly = "text_only"
    case textPlusOCR = "text_plus_ocr"
    case multimodalBalanced = "multimodal_balanced"
    case multimodalFull = "multimodal_full"
}

public enum TurnRole: String, Sendable, Codable, CaseIterable {
    case user
    case assistant
    case system
    case tool
}

public enum MemoryCategory: String, Sendable, Codable, CaseIterable {
    case identity
    case knowledge
    case context
    case instruction
    case uncertainty
}
