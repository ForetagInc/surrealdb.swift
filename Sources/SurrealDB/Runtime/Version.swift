import Foundation

/// Identifies this build of the SDK.
///
/// Worth having now that a build can embed a native database: "which version am
/// I running?" has two answers, and the Swift version alone does not pin the
/// engine.
public enum SurrealDBSDK {
    public static let version = "1.1.0-alpha.1"

    /// The surrealdb.c commit the embedded engine is built from, or `nil` when
    /// this build has no embedded support. Kept in step with
    /// `scripts/embedded/pin.env` by `scripts/check-version.sh`.
    public static let embeddedNativeRevision: String? = {
        #if SURREALDB_EMBEDDED
        return "039481e0c46fcd9c4096a9eaf85ec3a8fadf80ec"
        #else
        return nil
        #endif
    }()
}
