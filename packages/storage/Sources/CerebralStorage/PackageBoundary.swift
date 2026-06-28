/// Compile-time marker for the operational storage module.
///
/// `CerebralStorage` is the only portable package permitted to link the vendored
/// SQLite engine (`SwiftToolchainCSQLite`). It owns the SQLite wrapper, the
/// migration runner, and the operational repositories, keeping the C dependency
/// out of `CerebralCore` (which stays adapter-free) and `CerebralTools`.
public enum CerebralStoragePackage {
    public static let boundary = "storage"
}
