#if SURREALDB_EMBEDDED
import CSurrealDB
import Foundation

/// Owns an `sr_value_t*` produced by one of the `sr_value_*` constructors.
///
/// Every constructor hands back a Rust `Box::into_raw`, so exactly one
/// `sr_value_free` must run per value, on every path, including throws. Note
/// that `sr_object_insert` and `sr_array_push` *clone* what they are given, so
/// the caller always keeps ownership of what it built.
final class OwnedCValue {
    let pointer: UnsafeMutablePointer<sr_value_t>

    init(_ pointer: UnsafeMutablePointer<sr_value_t>) {
        self.pointer = pointer
    }

    deinit {
        sr_value_free(pointer)
    }
}

/// Owns an `sr_object_t`, which is passed to `sr_free_object` *by value*.
///
/// Still required after `sr_value_object(&object)`: that clones rather than
/// taking ownership, which reads like a move and is not one.
final class OwnedCObject {
    var object: sr_object_t

    init() {
        self.object = sr_object_new()
    }

    func insert(_ key: String, _ value: OwnedCValue) {
        key.withCString { sr_object_insert(&object, $0, value.pointer) }
    }

    deinit {
        sr_free_object(object)
    }
}

/// Owns the `sr_array_t*` chain that `sr_array_push` produces.
///
/// `sr_array_push` returns a *new* array and leaves the original untouched, so
/// every intermediate generation has to be freed. It also deep-clones the whole
/// prefix on each call, which is why the caller caps element counts.
final class OwnedCArray {
    private var pointer: UnsafeMutablePointer<sr_array_t>?
    /// False while `pointer` is the shell's own generation, which the shell
    /// frees, or after `take()` has handed ownership to the caller.
    private var ownsPointer = false

    init(seededBy shell: UnsafeMutablePointer<sr_value_t>) {
        self.pointer = shell.pointee.sr_value_array
    }

    func push(_ value: OwnedCValue) {
        guard let current = pointer, let next = sr_array_push(current, value.pointer) else { return }
        if ownsPointer {
            sr_array_free(current)
        }
        ownsPointer = true
        pointer = next
    }

    /// Hands the final array to the caller. Ownership moves out, so `deinit`
    /// stops caring about it.
    func take() -> UnsafeMutablePointer<sr_array_t>? {
        defer {
            ownsPointer = false
            pointer = nil
        }
        return pointer
    }

    deinit {
        if ownsPointer, let pointer {
            sr_array_free(pointer)
        }
    }
}
#endif
