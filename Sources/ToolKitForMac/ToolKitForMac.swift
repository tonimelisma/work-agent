// REQ: see PRODUCT.md "ToolKit: native tools as package products" — platform
// umbrella over domain targets, decided 2026-07-19: apps import one product,
// platform-true contents. Code lives in the domain targets (ToolKitFiles,
// ToolKitWeb, ToolKitInteraction); this file only re-exports them.
// ToolKitMacControl joins this umbrella when it exists.
@_exported import ToolKitFiles
@_exported import ToolKitInteraction
@_exported import ToolKitWeb
