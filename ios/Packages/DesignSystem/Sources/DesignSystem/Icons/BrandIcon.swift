// BrandIcon.swift — §30 Brand Icon Catalog
//
// Typed semantic icon names mapped to SF Symbol strings.
// Usage:
//   BrandIcon.ticket.image
//   BrandIcon.ticket.systemName
//   BrandIcon.ticket.accessibilityLabel

import SwiftUI

/// Typed catalog of every SF Symbol used across BizarreCRM.
///
/// Each case carries a stable semantic name (e.g. `.ticket`) that maps to
/// an SF Symbol string and a localised VoiceOver label. Adding a new symbol
/// to the app? Add a case here instead of sprinkling raw string literals.
public enum BrandIcon: String, CaseIterable, Sendable {

    // MARK: - Core entities

    /// Repair/service ticket
    case ticket                         = "ticket"
    /// Ticket (slashed/cancelled)
    case ticketSlash                    = "ticket.slash"
    /// Ticket (filled coupon/discount)
    case ticketFill                     = "ticket.fill"
    /// Customer / person
    case customer                       = "person.circle"
    /// Customer fill
    case customerFill                   = "person.circle.fill"
    /// Customer (generic person icon)
    case person                         = "person.fill"
    /// Multiple people / team
    case team                           = "person.3"
    /// Multiple people filled
    case teamFill                       = "person.3.fill"
    /// Invoice / document
    case invoice                        = "doc.text"
    /// Invoice filled
    case invoiceFill                    = "doc.text.fill"
    /// Receipt
    case receipt                        = "receipt.fill"
    /// Estimate / document with badge
    case estimate                       = "doc.badge.plus"

    // MARK: - Commerce & POS

    /// Shopping cart
    case cart                           = "cart.fill"
    /// Cart with removal badge
    case cartBadgeMinus                 = "cart.badge.minus"
    /// Barcode scanner
    case barcode                        = "barcode.viewfinder"
    /// Barcode (non-viewfinder)
    case barcodeScanner                 = "barcode"
    /// QR code scanner
    case qrCode                         = "qrcode.viewfinder"
    /// Credit card
    case creditCard                     = "creditcard.fill"
    /// Credit card scanner
    case creditCardViewfinder           = "creditcard.viewfinder"
    /// Dollar sign / money circle
    case dollar                         = "dollarsign.circle"
    /// Dollar sign filled
    case dollarFill                     = "dollarsign.circle.fill"
    /// Banknote
    case banknote                       = "banknote"
    /// Tag / label
    case tag                            = "tag"
    /// Tag filled
    case tagFill                        = "tag.fill"
    /// Tag slashed (no override)
    case tagSlash                       = "tag.slash"
    /// Percent sign
    case percent                        = "percent"
    /// Gift
    case gift                           = "gift.fill"
    /// Coupon / discount (same SF Symbol as ticketFill; distinct semantic case)
    case coupon                         = "ticket.fill.coupon"

    // MARK: - Inventory & Supply chain

    /// Shipping box (empty)
    case shippingBox                    = "shippingbox"
    /// Shipping box (filled)
    case shippingBoxFill                = "shippingbox.fill"
    /// Receiving — box with back arrow
    case shippingBoxReturn              = "shippingbox.and.arrow.backward"
    /// Table cells / grid view
    case tableCells                     = "tablecells"
    /// Table cells with badge
    case tableCellsBadge                = "tablecells.badge.ellipsis"
    /// List view
    case listBullet                     = "list.bullet"
    /// Device template (phones)
    case devicePhone                    = "iphone.gen3"
    /// Devices (laptop + phone)
    case devices                        = "laptopcomputer.and.iphone"
    /// Wrench and screwdriver (repair)
    case repairTool                     = "wrench.and.screwdriver"
    /// Wrench and screwdriver filled
    case repairToolFill                 = "wrench.and.screwdriver.fill"

    // MARK: - Navigation & disclosure

    /// Right chevron (disclosure)
    case chevronRight                   = "chevron.right"
    /// Left chevron
    case chevronLeft                    = "chevron.left"
    /// Down chevron
    case chevronDown                    = "chevron.down"
    /// Up chevron
    case chevronUp                      = "chevron.up"
    /// Up-down chevrons (reorder)
    case chevronUpDown                  = "chevron.up.chevron.down"
    /// Arrow right (transfer)
    case arrowRight                     = "arrow.right"
    /// Arrow up-right (external link)
    case arrowUpRight                   = "arrow.up.right"
    /// Arrow down-right
    case arrowDownRight                 = "arrow.down.right"
    /// Refresh / reload
    case refresh                        = "arrow.clockwise"
    /// Counter-clockwise refresh
    case refreshCounterclockwise        = "arrow.counterclockwise.circle"
    /// Sync / two arrows
    case sync                           = "arrow.triangle.2.circlepath"

    // MARK: - Feedback & status

    /// Checkmark
    case checkmark                      = "checkmark"
    /// Checkmark circle
    case checkmarkCircle                = "checkmark.circle"
    /// Checkmark circle filled
    case checkmarkCircleFill            = "checkmark.circle.fill"
    /// Checkmark square filled (checkbox)
    case checkmarkSquareFill            = "checkmark.square.fill"
    /// Empty square (unchecked)
    case square                         = "square"
    /// Checkmark seal (verified)
    case checkmarkSeal                  = "checkmark.seal"
    /// Checkmark seal filled
    case checkmarkSealFill              = "checkmark.seal.fill"
    /// Warning / exclamation triangle
    case warning                        = "exclamationmark.triangle.fill"
    /// Warning (outline)
    case warningOutline                 = "exclamationmark.triangle"
    /// Error / exclamation circle
    case errorCircle                    = "exclamationmark.circle.fill"
    /// Error circle (outline)
    case errorCircleOutline             = "exclamationmark.circle"
    /// Info circle
    case info                           = "info.circle"
    /// Info circle filled
    case infoFill                       = "info.circle.fill"
    /// Question mark circle
    case questionmark                   = "questionmark.circle"
    /// Flag (priority)
    case flag                           = "flag.fill"
    /// Star
    case star                           = "star"
    /// Star filled
    case starFill                       = "star.fill"
    /// Star slashed
    case starSlash                      = "star.slash"
    /// Heart (NPS)
    case heart                          = "heart.fill"
    /// Flame (streak)
    case flame                          = "flame.fill"

    // MARK: - Actions

    /// Add / plus
    case plus                           = "plus"
    /// Plus circle filled
    case plusCircleFill                 = "plus.circle.fill"
    /// Plus rectangle on folder
    case plusRectangleFolder            = "plus.rectangle.on.folder"
    /// Trash / delete
    case trash                          = "trash"
    /// Xmark / dismiss
    case xmark                          = "xmark"
    /// Xmark circle filled
    case xmarkCircleFill                = "xmark.circle.fill"
    /// Xmark bin filled
    case xmarkBinFill                   = "xmark.bin.fill"
    /// Minus circle filled
    case minusCircleFill                = "minus.circle.fill"
    /// Delete left (backspace)
    case deleteLeft                     = "delete.left"
    /// Pencil (edit)
    case pencil                         = "pencil"
    /// Pencil tip
    case pencilTip                      = "pencil.tip"
    /// Pencil and signature
    case pencilSignature                = "pencil.and.signature"
    /// Eraser
    case eraser                         = "eraser"
    /// Square and pencil (compose)
    case squarePencil                   = "square.and.pencil"
    /// Ellipsis circle (more actions)
    case ellipsisCircle                 = "ellipsis.circle"
    /// Filter (3 horizontal lines)
    case filter                         = "line.3.horizontal.decrease.circle"
    /// Filter active (filled)
    case filterFill                     = "line.3.horizontal.decrease.circle.fill"
    /// Magnifying glass (search)
    case magnifyingGlass                = "magnifyingglass"
    /// Magnifying glass circle
    case magnifyingGlassCircle          = "magnifyingglass.circle"
    /// Lock
    case lock                           = "lock.fill"
    /// Lock circle
    case lockCircle                     = "lock.circle"
    /// Lock circle filled
    case lockCircleFill                 = "lock.circle.fill"
    /// Lock shield
    case lockShield                     = "lock.shield"
    /// Lock shield filled
    case lockShieldFill                 = "lock.shield.fill"

    // MARK: - Communication

    /// SMS / message bubble
    case message                        = "message"
    /// Message fill
    case messageFill                    = "message.fill"
    /// Message badge circle
    case messageBadgeCircle             = "message.badge.circle"
    /// Message badge filled
    case messageBadgeFill               = "message.badge.filled.fill"
    /// Text bubble (templates)
    case textBubble                     = "text.bubble"
    /// Bubble conversation
    case bubbleConversation             = "bubble.left.and.bubble.right"
    /// Paper plane (send email)
    case paperPlane                     = "paperplane.fill"
    /// Envelope
    case envelope                       = "envelope"
    /// Envelope filled
    case envelopeFill                   = "envelope.fill"
    /// Envelope open filled (digest)
    case envelopeOpenFill               = "envelope.open.fill"
    /// Pin (pinned messages)
    case pin                            = "pin.fill"
    /// Archive box
    case archive                        = "archivebox.fill"
    /// Bell
    case bell                           = "bell"
    /// Bell badge
    case bellBadge                      = "bell.badge"
    /// Bell badge slashed
    case bellBadgeSlash                 = "bell.badge.slash"

    // MARK: - Scheduling & time

    /// Calendar
    case calendar                       = "calendar"
    /// Calendar circle
    case calendarCircle                 = "calendar.circle"
    /// Calendar badge plus
    case calendarBadgePlus              = "calendar.badge.plus"
    /// Clock
    case clock                          = "clock"
    /// Clock fill
    case clockFill                      = "clock.fill"
    /// Alarm
    case alarm                          = "alarm"
    /// Timer
    case timer                          = "timer"

    // MARK: - Employees & HR

    /// Chart bar (performance)
    case chartBar                       = "chart.bar.fill"
    /// Chart bar outline
    case chartBarOutline                = "chart.bar"
    /// Chart line trend
    case chartLineTrend                 = "chart.line.uptrend.xyaxis"
    /// Chart bar horizontal (expenses)
    case chartBarHorizontal             = "chart.bar.doc.horizontal"
    /// Graduationcap (training)
    case graduationCap                  = "graduationcap.fill"
    /// Commission / dollar badge (same SF Symbol as dollarFill; distinct semantic case)
    case commission                     = "dollarsign.circle.fill.commission"

    // MARK: - Settings & system

    /// Building (company/location)
    case building                       = "building.2"
    /// Building fill
    case buildingFill                   = "building.2.fill"
    /// Building columns (admin)
    case buildingColumns                = "building.columns.fill"
    /// Map pin
    case mapPin                         = "mappin.circle.fill"
    /// Map fill
    case mapFill                        = "map.fill"
    /// Location fill
    case locationFill                   = "location.fill"
    /// Settings / tools (same SF Symbol as repairTool; distinct semantic case)
    case settings                       = "wrench.and.screwdriver.settings"
    /// Bolt (kiosk/flash)
    case bolt                           = "bolt.fill"
    /// Lightbulb
    case lightbulb                      = "lightbulb.fill"
    /// Printer slashed (offline)
    case printerSlash                   = "printer.slash"
    /// WiFi slashed (offline)
    case wifiSlash                      = "wifi.slash"
    /// List clipboard
    case listClipboard                  = "list.clipboard"
    /// List bullet clipboard (kiosk queue)
    case listBulletClipboard            = "list.bullet.clipboard"
    /// Doc text search
    case docTextSearch                  = "doc.text.magnifyingglass"
    /// Eye (preview)
    case eye                            = "eye.fill"
    /// Eye slash (hidden)
    case eyeSlash                       = "eye.slash"
    /// Photo
    case photo                          = "photo"
    /// Photo stack
    case photoStack                     = "photo.stack"
    /// Photo on rectangle (before/after)
    case photoOnRectangle               = "photo.on.rectangle.angled"
    /// Camera badge plus
    case cameraBadgePlus                = "camera.badge.plus"
    /// Rectangle dashed (template)
    case rectangleDashed                = "rectangle.dashed"
    /// Sparkles
    case sparkles                       = "sparkles"
    /// Party popper (onboarding done)
    case partyPopper                    = "party.popper.fill"
    /// Moon (focus/DND)
    case moon                           = "moon.fill"
    /// Tray (empty state)
    case tray                           = "tray"

    // MARK: - Security & auth

    /// Key
    case key                            = "key"
    /// Key fill
    case keyFill                        = "key.fill"
    /// Person badge key (passkey)
    case personBadgeKey                 = "person.badge.key.fill"
    /// Number circle (2FA)
    case numberCircle                   = "number.circle"
    /// Checkmark shield (security check)
    case checkmarkShield                = "checkmark.shield"
    /// Checkmark shield fill
    case checkmarkShieldFill            = "checkmark.shield.fill"
}

// MARK: - §30.8 Icon role (fill vs outline)

/// Semantic role that governs the fill/outline choice per §30.8.
///
/// - `navigation`: outline (standard unselected nav / toolbar icons).
/// - `active`: fill (selected tab, active toggle, currently-open item).
///
/// Use `BrandIcon.resolvedSymbolName(for:)` to automatically pick the
/// correct SF Symbol variant.
public enum BrandIconRole: Sendable {
    case navigation
    case active
}

// MARK: - SwiftUI accessors

public extension BrandIcon {

    /// A SwiftUI `Image` wrapping the corresponding SF Symbol.
    var image: Image {
        Image(systemName: systemName)
    }

    // MARK: — §30.8 Role-sensitive symbol name

    /// Returns the correct SF Symbol variant for `role`:
    /// - `.navigation` → outline (no `.fill` suffix where the pair exists).
    /// - `.active`     → fill.
    ///
    /// Falls back to `systemName` when the icon does not have a distinct
    /// fill/outline pair.
    public func resolvedSymbolName(for role: BrandIconRole) -> String {
        switch role {
        case .active: return filledSystemName
        case .navigation: return outlineSystemName
        }
    }

    /// SF Symbol name for the outline (navigation) variant.
    private var outlineSystemName: String {
        // Symbols that have both outline and fill forms.
        switch self {
        case .customer:         return "person.circle"
        case .invoice:          return "doc.text"
        case .message:          return "message"
        case .envelope:         return "envelope"
        case .bell:             return "bell"
        case .calendar:         return "calendar"
        case .clock:            return "clock"
        case .lock:             return "lock"
        case .star:             return "star"
        case .heart:            return "heart"
        case .checkmarkCircle:  return "checkmark.circle"
        case .checkmarkSeal:    return "checkmark.seal"
        case .buildingFill:     return "building.2"
        default:                return systemName
        }
    }

    /// SF Symbol name for the fill (active) variant.
    private var filledSystemName: String {
        switch self {
        case .customer:         return "person.circle.fill"
        case .invoice:          return "doc.text.fill"
        case .message:          return "message.fill"
        case .envelope:         return "envelope.fill"
        case .bell:             return "bell.fill"
        case .calendar:         return "calendar.fill"
        case .clock:            return "clock.fill"
        case .lock:             return "lock.fill"
        case .star:             return "star.fill"
        case .heart:            return "heart.fill"
        case .checkmarkCircle:  return "checkmark.circle.fill"
        case .checkmarkSeal:    return "checkmark.seal.fill"
        case .building:         return "building.2.fill"
        default:                return systemName
        }
    }

    /// The raw SF Symbol name string.
    /// Some cases share a symbol but need unique raw values for the enum;
    /// we store the sentinel as "<symbol>.<semantic>" and strip it here.
    var systemName: String {
        switch self {
        case .coupon:     return "ticket.fill"
        case .commission: return "dollarsign.circle.fill"
        case .settings:   return "wrench.and.screwdriver"
        default:          return rawValue
        }
    }

    /// Localised VoiceOver label for the icon.
    ///
    /// Using `NSLocalizedString` so strings are extracted by the standard
    /// toolchain. The `comment:` includes the SF Symbol name for translator context.
    var accessibilityLabel: String {
        switch self {
        // Core entities
        case .ticket:                    return NSLocalizedString("Ticket", comment: "SF: ticket")
        case .ticketSlash:               return NSLocalizedString("Cancelled Ticket", comment: "SF: ticket.slash")
        case .ticketFill:                return NSLocalizedString("Ticket", comment: "SF: ticket.fill")
        case .customer:                  return NSLocalizedString("Customer", comment: "SF: person.circle")
        case .customerFill:              return NSLocalizedString("Customer", comment: "SF: person.circle.fill")
        case .person:                    return NSLocalizedString("Person", comment: "SF: person.fill")
        case .team:                      return NSLocalizedString("Team", comment: "SF: person.3")
        case .teamFill:                  return NSLocalizedString("Team", comment: "SF: person.3.fill")
        case .invoice:                   return NSLocalizedString("Invoice", comment: "SF: doc.text")
        case .invoiceFill:               return NSLocalizedString("Invoice", comment: "SF: doc.text.fill")
        case .receipt:                   return NSLocalizedString("Receipt", comment: "SF: receipt.fill")
        case .estimate:                  return NSLocalizedString("Estimate", comment: "SF: doc.badge.plus")
        // Commerce & POS
        case .cart:                      return NSLocalizedString("Cart", comment: "SF: cart.fill")
        case .cartBadgeMinus:            return NSLocalizedString("Remove from Cart", comment: "SF: cart.badge.minus")
        case .barcode:                   return NSLocalizedString("Scan Barcode", comment: "SF: barcode.viewfinder")
        case .barcodeScanner:            return NSLocalizedString("Barcode", comment: "SF: barcode")
        case .qrCode:                    return NSLocalizedString("Scan QR Code", comment: "SF: qrcode.viewfinder")
        case .creditCard:                return NSLocalizedString("Credit Card", comment: "SF: creditcard.fill")
        case .creditCardViewfinder:      return NSLocalizedString("Scan Card", comment: "SF: creditcard.viewfinder")
        case .dollar:                    return NSLocalizedString("Dollar", comment: "SF: dollarsign.circle")
        case .dollarFill:                return NSLocalizedString("Dollar", comment: "SF: dollarsign.circle.fill")
        case .banknote:                  return NSLocalizedString("Cash", comment: "SF: banknote")
        case .tag:                       return NSLocalizedString("Tag", comment: "SF: tag")
        case .tagFill:                   return NSLocalizedString("Tag", comment: "SF: tag.fill")
        case .tagSlash:                  return NSLocalizedString("No Tag", comment: "SF: tag.slash")
        case .percent:                   return NSLocalizedString("Percent", comment: "SF: percent")
        case .gift:                      return NSLocalizedString("Gift", comment: "SF: gift.fill")
        case .coupon:                    return NSLocalizedString("Coupon", comment: "SF: ticket.fill — coupon use")
        // Inventory & Supply chain
        case .shippingBox:               return NSLocalizedString("Inventory", comment: "SF: shippingbox")
        case .shippingBoxFill:           return NSLocalizedString("Inventory", comment: "SF: shippingbox.fill")
        case .shippingBoxReturn:         return NSLocalizedString("Return Shipment", comment: "SF: shippingbox.and.arrow.backward")
        case .tableCells:                return NSLocalizedString("Table View", comment: "SF: tablecells")
        case .tableCellsBadge:           return NSLocalizedString("Table View", comment: "SF: tablecells.badge.ellipsis")
        case .listBullet:                return NSLocalizedString("List View", comment: "SF: list.bullet")
        case .devicePhone:               return NSLocalizedString("Device", comment: "SF: iphone.gen3")
        case .devices:                   return NSLocalizedString("Devices", comment: "SF: laptopcomputer.and.iphone")
        case .repairTool:                return NSLocalizedString("Repair", comment: "SF: wrench.and.screwdriver")
        case .repairToolFill:            return NSLocalizedString("Repair", comment: "SF: wrench.and.screwdriver.fill")
        // Navigation & disclosure
        case .chevronRight:              return NSLocalizedString("More", comment: "SF: chevron.right")
        case .chevronLeft:               return NSLocalizedString("Back", comment: "SF: chevron.left")
        case .chevronDown:               return NSLocalizedString("Expand", comment: "SF: chevron.down")
        case .chevronUp:                 return NSLocalizedString("Collapse", comment: "SF: chevron.up")
        case .chevronUpDown:             return NSLocalizedString("Reorder", comment: "SF: chevron.up.chevron.down")
        case .arrowRight:                return NSLocalizedString("Next", comment: "SF: arrow.right")
        case .arrowUpRight:              return NSLocalizedString("Open", comment: "SF: arrow.up.right")
        case .arrowDownRight:            return NSLocalizedString("Trend Down", comment: "SF: arrow.down.right")
        case .refresh:                   return NSLocalizedString("Refresh", comment: "SF: arrow.clockwise")
        case .refreshCounterclockwise:   return NSLocalizedString("Reset", comment: "SF: arrow.counterclockwise.circle")
        case .sync:                      return NSLocalizedString("Sync", comment: "SF: arrow.triangle.2.circlepath")
        // Feedback & status
        case .checkmark:                 return NSLocalizedString("Done", comment: "SF: checkmark")
        case .checkmarkCircle:           return NSLocalizedString("Completed", comment: "SF: checkmark.circle")
        case .checkmarkCircleFill:       return NSLocalizedString("Completed", comment: "SF: checkmark.circle.fill")
        case .checkmarkSquareFill:       return NSLocalizedString("Checked", comment: "SF: checkmark.square.fill")
        case .square:                    return NSLocalizedString("Unchecked", comment: "SF: square")
        case .checkmarkSeal:             return NSLocalizedString("Verified", comment: "SF: checkmark.seal")
        case .checkmarkSealFill:         return NSLocalizedString("Verified", comment: "SF: checkmark.seal.fill")
        case .warning:                   return NSLocalizedString("Warning", comment: "SF: exclamationmark.triangle.fill")
        case .warningOutline:            return NSLocalizedString("Warning", comment: "SF: exclamationmark.triangle")
        case .errorCircle:               return NSLocalizedString("Error", comment: "SF: exclamationmark.circle.fill")
        case .errorCircleOutline:        return NSLocalizedString("Error", comment: "SF: exclamationmark.circle")
        case .info:                      return NSLocalizedString("Information", comment: "SF: info.circle")
        case .infoFill:                  return NSLocalizedString("Information", comment: "SF: info.circle.fill")
        case .questionmark:              return NSLocalizedString("Help", comment: "SF: questionmark.circle")
        case .flag:                      return NSLocalizedString("Flagged", comment: "SF: flag.fill")
        case .star:                      return NSLocalizedString("Star", comment: "SF: star")
        case .starFill:                  return NSLocalizedString("Starred", comment: "SF: star.fill")
        case .starSlash:                 return NSLocalizedString("Unstarred", comment: "SF: star.slash")
        case .heart:                     return NSLocalizedString("Favorite", comment: "SF: heart.fill")
        case .flame:                     return NSLocalizedString("Streak", comment: "SF: flame.fill")
        // Actions
        case .plus:                      return NSLocalizedString("Add", comment: "SF: plus")
        case .plusCircleFill:            return NSLocalizedString("Add", comment: "SF: plus.circle.fill")
        case .plusRectangleFolder:       return NSLocalizedString("Import", comment: "SF: plus.rectangle.on.folder")
        case .trash:                     return NSLocalizedString("Delete", comment: "SF: trash")
        case .xmark:                     return NSLocalizedString("Close", comment: "SF: xmark")
        case .xmarkCircleFill:           return NSLocalizedString("Remove", comment: "SF: xmark.circle.fill")
        case .xmarkBinFill:              return NSLocalizedString("Clear", comment: "SF: xmark.bin.fill")
        case .minusCircleFill:           return NSLocalizedString("Remove", comment: "SF: minus.circle.fill")
        case .deleteLeft:                return NSLocalizedString("Delete", comment: "SF: delete.left")
        case .pencil:                    return NSLocalizedString("Edit", comment: "SF: pencil")
        case .pencilTip:                 return NSLocalizedString("Annotate", comment: "SF: pencil.tip")
        case .pencilSignature:           return NSLocalizedString("Sign", comment: "SF: pencil.and.signature")
        case .eraser:                    return NSLocalizedString("Erase", comment: "SF: eraser")
        case .squarePencil:              return NSLocalizedString("Compose", comment: "SF: square.and.pencil")
        case .ellipsisCircle:            return NSLocalizedString("More Options", comment: "SF: ellipsis.circle")
        case .filter:                    return NSLocalizedString("Filter", comment: "SF: line.3.horizontal.decrease.circle")
        case .filterFill:                return NSLocalizedString("Filter Active", comment: "SF: line.3.horizontal.decrease.circle.fill")
        case .magnifyingGlass:           return NSLocalizedString("Search", comment: "SF: magnifyingglass")
        case .magnifyingGlassCircle:     return NSLocalizedString("Search", comment: "SF: magnifyingglass.circle")
        case .lock:                      return NSLocalizedString("Locked", comment: "SF: lock.fill")
        case .lockCircle:                return NSLocalizedString("Locked", comment: "SF: lock.circle")
        case .lockCircleFill:            return NSLocalizedString("Locked", comment: "SF: lock.circle.fill")
        case .lockShield:                return NSLocalizedString("Secure", comment: "SF: lock.shield")
        case .lockShieldFill:            return NSLocalizedString("Secure", comment: "SF: lock.shield.fill")
        // Communication
        case .message:                   return NSLocalizedString("Message", comment: "SF: message")
        case .messageFill:               return NSLocalizedString("Message", comment: "SF: message.fill")
        case .messageBadgeCircle:        return NSLocalizedString("New Message", comment: "SF: message.badge.circle")
        case .messageBadgeFill:          return NSLocalizedString("New Message", comment: "SF: message.badge.filled.fill")
        case .textBubble:                return NSLocalizedString("Message Template", comment: "SF: text.bubble")
        case .bubbleConversation:        return NSLocalizedString("Conversation", comment: "SF: bubble.left.and.bubble.right")
        case .paperPlane:                return NSLocalizedString("Send", comment: "SF: paperplane.fill")
        case .envelope:                  return NSLocalizedString("Email", comment: "SF: envelope")
        case .envelopeFill:              return NSLocalizedString("Email", comment: "SF: envelope.fill")
        case .envelopeOpenFill:          return NSLocalizedString("Open Email", comment: "SF: envelope.open.fill")
        case .pin:                       return NSLocalizedString("Pinned", comment: "SF: pin.fill")
        case .archive:                   return NSLocalizedString("Archived", comment: "SF: archivebox.fill")
        case .bell:                      return NSLocalizedString("Notifications", comment: "SF: bell")
        case .bellBadge:                 return NSLocalizedString("Notifications", comment: "SF: bell.badge")
        case .bellBadgeSlash:            return NSLocalizedString("Notifications Off", comment: "SF: bell.badge.slash")
        // Scheduling & time
        case .calendar:                  return NSLocalizedString("Calendar", comment: "SF: calendar")
        case .calendarCircle:            return NSLocalizedString("Calendar", comment: "SF: calendar.circle")
        case .calendarBadgePlus:         return NSLocalizedString("Add to Calendar", comment: "SF: calendar.badge.plus")
        case .clock:                     return NSLocalizedString("Time", comment: "SF: clock")
        case .clockFill:                 return NSLocalizedString("Time", comment: "SF: clock.fill")
        case .alarm:                     return NSLocalizedString("Alarm", comment: "SF: alarm")
        case .timer:                     return NSLocalizedString("Timer", comment: "SF: timer")
        // Employees & HR
        case .chartBar:                  return NSLocalizedString("Chart", comment: "SF: chart.bar.fill")
        case .chartBarOutline:           return NSLocalizedString("Chart", comment: "SF: chart.bar")
        case .chartLineTrend:            return NSLocalizedString("Revenue Trend", comment: "SF: chart.line.uptrend.xyaxis")
        case .chartBarHorizontal:        return NSLocalizedString("Expenses", comment: "SF: chart.bar.doc.horizontal")
        case .graduationCap:             return NSLocalizedString("Training", comment: "SF: graduationcap.fill")
        case .commission:                return NSLocalizedString("Commission", comment: "SF: dollarsign.circle.fill — commission use")
        // Settings & system
        case .building:                  return NSLocalizedString("Location", comment: "SF: building.2")
        case .buildingFill:              return NSLocalizedString("Location", comment: "SF: building.2.fill")
        case .buildingColumns:           return NSLocalizedString("Admin", comment: "SF: building.columns.fill")
        case .mapPin:                    return NSLocalizedString("Location", comment: "SF: mappin.circle.fill")
        case .mapFill:                   return NSLocalizedString("Map", comment: "SF: map.fill")
        case .locationFill:              return NSLocalizedString("Current Location", comment: "SF: location.fill")
        case .settings:                  return NSLocalizedString("Settings", comment: "SF: wrench.and.screwdriver — settings use")
        case .bolt:                      return NSLocalizedString("Active", comment: "SF: bolt.fill")
        case .lightbulb:                 return NSLocalizedString("Tip", comment: "SF: lightbulb.fill")
        case .printerSlash:              return NSLocalizedString("Printer Offline", comment: "SF: printer.slash")
        case .wifiSlash:                 return NSLocalizedString("Offline", comment: "SF: wifi.slash")
        case .listClipboard:             return NSLocalizedString("List", comment: "SF: list.clipboard")
        case .listBulletClipboard:       return NSLocalizedString("Queue", comment: "SF: list.bullet.clipboard")
        case .docTextSearch:             return NSLocalizedString("Search Document", comment: "SF: doc.text.magnifyingglass")
        case .eye:                       return NSLocalizedString("Show", comment: "SF: eye.fill")
        case .eyeSlash:                  return NSLocalizedString("Hide", comment: "SF: eye.slash")
        case .photo:                     return NSLocalizedString("Photo", comment: "SF: photo")
        case .photoStack:                return NSLocalizedString("Photos", comment: "SF: photo.stack")
        case .photoOnRectangle:          return NSLocalizedString("Before and After Photo", comment: "SF: photo.on.rectangle.angled")
        case .cameraBadgePlus:           return NSLocalizedString("Add Photo", comment: "SF: camera.badge.plus")
        case .rectangleDashed:           return NSLocalizedString("Template", comment: "SF: rectangle.dashed")
        case .sparkles:                  return NSLocalizedString("New", comment: "SF: sparkles")
        case .partyPopper:               return NSLocalizedString("Complete", comment: "SF: party.popper.fill")
        case .moon:                      return NSLocalizedString("Do Not Disturb", comment: "SF: moon.fill")
        case .tray:                      return NSLocalizedString("Empty", comment: "SF: tray")
        // Security & auth
        case .key:                       return NSLocalizedString("Key", comment: "SF: key")
        case .keyFill:                   return NSLocalizedString("Key", comment: "SF: key.fill")
        case .personBadgeKey:            return NSLocalizedString("Passkey", comment: "SF: person.badge.key.fill")
        case .numberCircle:              return NSLocalizedString("Two-Factor Code", comment: "SF: number.circle")
        case .checkmarkShield:           return NSLocalizedString("Security Check", comment: "SF: checkmark.shield")
        case .checkmarkShieldFill:       return NSLocalizedString("Security Check", comment: "SF: checkmark.shield.fill")
        }
    }
}
