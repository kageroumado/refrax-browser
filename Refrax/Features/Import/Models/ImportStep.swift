/// Steps in the comprehensive import wizard flow.
enum ImportStep {
    case selectBrowser
    case selectProfile
    case safariExportGuide
    case selectDataTypes
    case configureOptions
    case importing
    case credentialConflicts
    case summary
    case failedBookmarks
    case extensionPreview
}
