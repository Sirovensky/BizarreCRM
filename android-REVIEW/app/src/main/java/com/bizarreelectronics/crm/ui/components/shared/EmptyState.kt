package com.bizarreelectronics.crm.ui.components.shared

// NOTE: This file intentionally re-exports [EmptyState] from SharedComponents.kt via
// a type-alias-free import so that Wave 4 agents can import from this canonical path:
//
//   import com.bizarreelectronics.crm.ui.components.shared.EmptyState
//
// [EmptyState] itself is defined in SharedComponents.kt (same package).  No duplicate
// implementation is needed — this file is intentionally empty except for this comment.
//
// §66.1: EmptyState is already fully implemented in SharedComponents.kt with:
//   - WaveDivider at top (illustrative wave = the "illustration" slot)
//   - headlineMedium headline (Barlow Condensed SemiBold via Wave 1 Typography)
//   - onSurfaceVariant subtitle (helpful, not frustrated — §66 tone)
//   - optional CTA action lambda
//   - icon slot (ImageVector) with contentDescription = null (decorative;
//     sibling Title Text carries the announcement — D5-1 compliance)
//
// String keys for standard empty states live in strings.xml (§66):
//   tickets_empty_title / tickets_empty_subtitle
//   customers_empty_title / customers_empty_subtitle
