// Mirrors enum class BackupStatus in contents/lib/pbstypes.h. The controller
// publishes these as plain ints, so keep both lists in the same order.
export const Unknown = 0
export const Current = 1
export const Warning = 2
export const Stale = 3
export const Never = 4
export const Excluded = 5
export const Ambiguous = 6
