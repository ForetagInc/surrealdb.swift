import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct SurrealDBMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SurrealModelMacro.self,
        WhereMacro.self,
        SelectMacro.self,
        CreateMacro.self,
        UpdateMacro.self,
        UpsertMacro.self,
        DeleteMacro.self,
        LiveMacro.self,
    ]
}

enum SurrealMacroError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let value):
            return value
        }
    }
}

public enum SurrealModelMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard case .argumentList(let arguments) = node.arguments,
              let firstArgument = arguments.first,
              let tableLiteral = firstArgument.expression.as(StringLiteralExprSyntax.self),
              tableLiteral.segments.count == 1,
              case .stringSegment(let segment)? = tableLiteral.segments.first
        else {
            throw SurrealMacroError.message("@SurrealModel requires a single static table string literal.")
        }

        let tableName = segment.content.text
        let typeName = try declarationTypeName(declaration)

        var fieldMembers: [DeclSyntax] = []

        for member in declaration.memberBlock.members {
            guard let variableDecl = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }

            if variableDecl.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) {
                continue
            }

            for binding in variableDecl.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                    continue
                }

                let fieldType = binding.typeAnnotation?.type.trimmedDescription ?? "Any"
                fieldMembers.append(
                    "public static let \(raw: identifier) = SurrealField<\(raw: typeName), \(raw: fieldType)>(\(literal: identifier))"
                )
            }
        }

        let fieldsDecl: DeclSyntax
        if fieldMembers.isEmpty {
            fieldsDecl = "public enum Fields {}"
        } else {
            let joined = fieldMembers.map(\.description).joined(separator: "\n")
            fieldsDecl = """
            public enum Fields {
            \(raw: joined)
            }
            """
        }

        return [
            "public static let surrealTable: String = \(literal: tableName)",
            fieldsDecl,
        ]
    }

    public static func expansion(
        of _: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        _ = declaration
        return [
            try ExtensionDeclSyntax("extension \(type.trimmed): SurrealModel {}")
        ]
    }

    private static func declarationTypeName(_ declaration: some DeclGroupSyntax) throws -> String {
        if let declaration = declaration.as(StructDeclSyntax.self) {
            return declaration.name.text
        }
        if let declaration = declaration.as(ClassDeclSyntax.self) {
            return declaration.name.text
        }
        if let declaration = declaration.as(ActorDeclSyntax.self) {
            return declaration.name.text
        }

        throw SurrealMacroError.message("@SurrealModel can only be attached to struct, class, or actor declarations.")
    }
}

public enum WhereMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in _: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let expression = node.arguments.first?.expression else {
            throw SurrealMacroError.message("#where requires one SurrealPredicate expression argument.")
        }
        return ExprSyntax(expression)
    }
}

public enum SelectMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        try expand(node, function: "select", context: context)
    }
}

public enum CreateMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        try expand(node, function: "create", context: context)
    }
}

public enum UpdateMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        try expand(node, function: "update", context: context)
    }
}

public enum UpsertMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        try expand(node, function: "upsert", context: context)
    }
}

public enum DeleteMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        try expand(node, function: "delete", context: context)
    }
}

public enum LiveMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        try expand(node, function: "live", context: context)
    }
}

private func expand(
    _ node: some FreestandingMacroExpansionSyntax,
    function: String,
    context _: some MacroExpansionContext
) throws -> ExprSyntax {
    guard !node.arguments.isEmpty else {
        throw SurrealMacroError.message("#\(function) requires at least a model type argument.")
    }

    let argumentList = node.arguments.map(\.description).joined(separator: ", ")
    return "SurrealDSL.\(raw: function)(\(raw: argumentList))"
}
