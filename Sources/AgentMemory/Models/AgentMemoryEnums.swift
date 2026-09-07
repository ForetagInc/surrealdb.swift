import Foundation

/// Retrieval strategy for a document query.
public enum QueryMode: String, Sendable, Codable, CaseIterable {
    case hybrid
    case vector
    case bm25
    case hybridGraph = "hybrid_graph"
}

/// Lifecycle status of an ingested document as it moves through the pipeline.
public enum DocumentStatus: String, Sendable, Codable, CaseIterable {
    case queued
    case extracting
    case chunking
    case embedding
    case keywording
    case extractingNodes = "extracting_nodes"
    case ready
    case failed
}

/// Role attached to a conversation turn or fact.
public enum TurnRole: String, Sendable, Codable, CaseIterable {
    case user
    case assistant
    case system
    case tool
}

/// Memory tier a fact, attribute, or relation belongs to.
public enum MemoryCategory: String, Sendable, Codable, CaseIterable {
    case identity
    case knowledge
    case context
}

/// How aggressively the server extracts structured memory from ingested facts.
public enum InferMode: String, Sendable, Codable, CaseIterable {
    case full
    case triples
    case preview
    case none
}

/// Whether a batch of messages is extracted per message or as one conversation.
public enum BatchExtractionMode: String, Sendable, Codable, CaseIterable {
    case perMessage = "per_message"
    case wholeConversation = "whole_conversation"
}

/// Edge kinds available to graph-expanded document retrieval.
public enum GraphEdgeKind: String, Sendable, Codable, CaseIterable {
    case knowledgeHasKeyword = "knowledge_has_keyword"
    case sectionMatch = "section_match"
    case documentLink = "document_link"
    case documentSummary = "document_summary"
    case keywordCooccurrence = "keyword_cooccurrence"
    case hybridGraph = "hybrid_graph"
}

/// Origin of a memory hit returned by a memory query.
public enum ResultKind: String, Sendable, Codable, CaseIterable {
    case attribute
    case entity
    case chunk
    case memoryChunk = "memory_chunk"
    case section
}

/// Resolution tier that served a memory query.
public enum Tier: String, Sendable, Codable, CaseIterable {
    case direct
    case cache
    case hybrid
    case fullContext = "full_context"
}

/// Classification the router assigned to a memory query.
public enum QueryKind: String, Sendable, Codable, CaseIterable {
    case directLookup = "direct_lookup"
    case hybrid
    case fullContext = "full_context"
}
