import Foundation

// MARK: - HelpArticleCatalog

/// Bundled static article catalog (15+ articles covering all major features).
public enum HelpArticleCatalog {

    /// All bundled articles.
    public static let all: [HelpArticle] = [
        gettingStarted,
        creatingATicket,
        posBasics,
        acceptingPayments,
        managingInventory,
        settingUpPrinters,
        blockchypPairing,
        barcodeScanning,
        customerManagement,
        refunds,
        endOfDayCashRegister,
        dailyReports,
        smsMessaging,
        appointmentScheduling,
        loyaltyProgram
    ]

    // MARK: - Getting Started

    static let gettingStarted = HelpArticle(
        id: "help.getting-started",
        title: "Getting started",
        category: .gettingStarted,
        markdown: """
        # Getting Started with BizarreCRM

        Welcome! This guide walks you through your first session.

        ## 1. Enter your server URL
        On the login screen enter the URL your administrator provided, for example `https://shop.bizarrecrm.com`.

        ## 2. Sign in
        Enter your username and password. If your shop requires 2-factor authentication you will be prompted for a code.

        ## 3. Explore the Dashboard
        After signing in you land on the Dashboard. Tap any tile to dive into that domain.

        ## Next steps
        - **Tickets** — manage service jobs
        - **Customers** — view and edit customer records
        - **POS** — accept payments
        """,
        tags: ["login", "setup", "first time", "onboarding"],
        relatedArticleIds: ["help.creating-a-ticket", "help.pos-basics"]
    )

    // MARK: - Creating a Ticket

    static let creatingATicket = HelpArticle(
        id: "help.creating-a-ticket",
        title: "Creating a ticket",
        category: .tickets,
        markdown: """
        # Creating a Ticket

        A ticket tracks a repair or service job from intake to completion.

        ## Steps
        1. Tap **Tickets** from the Dashboard.
        2. Tap the **+** button (bottom-right on iPhone; toolbar on iPad).
        3. Select or create a **customer**.
        4. Add a **device** and **problem description**.
        5. Tap **Save** — the ticket is created and appears in the list.

        ## Assigning a Technician
        Open the ticket and tap **Assignee**. Pick from the staff list.

        ## Status Flow
        `Intake` → `In Progress` → `Waiting for Parts` → `Ready` → `Closed`
        """,
        tags: ["ticket", "repair", "job", "create"],
        relatedArticleIds: ["help.getting-started"]
    )

    // MARK: - POS Basics

    static let posBasics = HelpArticle(
        id: "help.pos-basics",
        title: "POS basics",
        category: .payments,
        markdown: """
        # POS Basics

        The Point of Sale screen lets you ring up products and services.

        ## Opening a Sale
        Tap **POS** from the tab bar or Dashboard.

        ## Adding Items
        - Tap a product tile, or
        - Scan a barcode, or
        - Type in the search bar.

        ## Finishing the Sale
        1. Tap **Checkout**.
        2. Select a **payment method** (card, cash, gift card, etc.).
        3. Follow the on-screen prompts.
        4. The receipt can be printed or sent via SMS/email.
        """,
        tags: ["pos", "sale", "checkout", "point of sale"],
        relatedArticleIds: ["help.accepting-payments", "help.barcode-scanning"]
    )

    // MARK: - Accepting Payments

    static let acceptingPayments = HelpArticle(
        id: "help.accepting-payments",
        title: "Accepting payments",
        category: .payments,
        markdown: """
        # Accepting Payments

        BizarreCRM supports multiple payment methods.

        ## Card Payments
        Tap **Card** at checkout. The BlockChyp terminal prompts the customer.

        ## Cash
        Enter the amount tendered. The app calculates change.

        ## Split Tender
        Tap **Split** to accept multiple payment methods on one transaction.

        ## Offline Payments
        When offline, cash-only payments queue locally and sync when connectivity is restored.
        """,
        tags: ["payment", "card", "cash", "BlockChyp", "split"],
        relatedArticleIds: ["help.pos-basics", "help.refunds"]
    )

    // MARK: - Managing Inventory

    static let managingInventory = HelpArticle(
        id: "help.managing-inventory",
        title: "Managing inventory",
        category: .inventory,
        markdown: """
        # Managing Inventory

        Keep your stock accurate so sales and orders flow smoothly.

        ## Viewing Stock
        Go to **Inventory** → **Items**. Filter by category or search by name/SKU.

        ## Adjusting Stock
        Open an item → tap **Adjust Stock** → enter the new quantity and a reason.

        ## Low-Stock Alerts
        Set a **reorder point** on each item. When stock falls below this level you receive a push notification.

        ## Purchase Orders
        Tap **+** on the Inventory screen to create a purchase order.
        """,
        tags: ["inventory", "stock", "reorder", "sku"],
        relatedArticleIds: []
    )

    // MARK: - Setting Up Printers

    static let settingUpPrinters = HelpArticle(
        id: "help.setting-up-printers",
        title: "Setting up printers",
        category: .hardware,
        markdown: """
        # Setting Up Printers

        BizarreCRM supports Epson/Star ESC/POS printers over Wi-Fi and Bluetooth Classic.

        ## Adding a Printer
        1. Go to **Settings** → **Integrations** → **Printers**.
        2. Tap **Scan** to discover nearby printers.
        3. Select your printer from the list.

        ## Test Print
        Tap **Test Print** to verify the connection.

        ## Troubleshooting
        - Ensure the printer is on the same Wi-Fi network (for TCP printers).
        - For Bluetooth, pair the printer in iOS **Settings → Bluetooth** first.
        """,
        tags: ["printer", "receipt", "Bluetooth", "ESC/POS"],
        relatedArticleIds: ["help.pos-basics"]
    )

    // MARK: - BlockChyp Pairing

    static let blockchypPairing = HelpArticle(
        id: "help.blockchyp-pairing",
        title: "BlockChyp pairing",
        category: .hardware,
        markdown: """
        # BlockChyp Terminal Pairing

        BlockChyp is the card-present payment terminal integrated with BizarreCRM.

        ## First-Time Pairing
        1. Power on the BlockChyp terminal.
        2. In BizarreCRM go to **Settings** → **Integrations** → **BlockChyp**.
        3. Tap **Pair Terminal** and enter the pairing code shown on the terminal screen.

        ## Re-pairing
        If the terminal loses its pairing (e.g., after a factory reset), repeat the steps above.

        ## Test Transaction
        Run a **$0.01 test charge** to confirm the terminal is live.
        """,
        tags: ["BlockChyp", "terminal", "card", "pair", "payment"],
        relatedArticleIds: ["help.accepting-payments"]
    )

    // MARK: - Barcode Scanning

    static let barcodeScanning = HelpArticle(
        id: "help.barcode-scanning",
        title: "Barcode scanning",
        category: .inventory,
        markdown: """
        # Barcode Scanning

        Use the camera or a Bluetooth barcode scanner.

        ## Camera Scan
        Tap the **barcode** icon anywhere a scan is expected. Hold the camera steady over the barcode.

        ## Bluetooth Scanner
        Pair an HID-profile scanner via iOS **Settings → Bluetooth**. It acts as a keyboard; taps the active field automatically.

        ## Supported Formats
        Code 128, Code 39, EAN-13, EAN-8, QR Code, Data Matrix.

        ## Troubleshooting
        - Ensure camera permission is granted.
        - Clean the barcode label and try again with better lighting.
        """,
        tags: ["barcode", "scan", "camera", "scanner"],
        relatedArticleIds: ["help.managing-inventory"]
    )

    // MARK: - Customer Management

    static let customerManagement = HelpArticle(
        id: "help.customer-management",
        title: "Customer management",
        category: .customers,
        markdown: """
        # Customer Management

        All customer records are searchable and linked to tickets, invoices, and appointments.

        ## Creating a Customer
        Tap **Customers** → **+**. Fill in at minimum a name and phone number or email.

        ## Editing
        Open a customer → tap **Edit** (pencil icon).

        ## Merging Duplicates
        On the customer detail screen tap **...** → **Merge**. Search for the duplicate and confirm.

        ## Communication History
        Every SMS and email sent from BizarreCRM is logged under **Communications**.
        """,
        tags: ["customer", "contact", "CRM", "merge"],
        relatedArticleIds: ["help.sms-messaging"]
    )

    // MARK: - Refunds

    static let refunds = HelpArticle(
        id: "help.refunds",
        title: "Refunds",
        category: .payments,
        markdown: """
        # Refunds

        Process a full or partial refund from a completed sale.

        ## Full Refund
        1. Open the invoice.
        2. Tap **Refund** → **Full Refund**.
        3. Confirm.

        ## Partial Refund
        1. Open the invoice → tap **Refund** → **Partial Refund**.
        2. Enter the amount or select specific line items.
        3. Confirm.

        ## Return to Inventory
        Toggle **Restock items** during the refund to return items to inventory automatically.
        """,
        tags: ["refund", "return", "reverse", "void"],
        relatedArticleIds: ["help.accepting-payments"]
    )

    // MARK: - End-of-day Cash Register

    static let endOfDayCashRegister = HelpArticle(
        id: "help.end-of-day",
        title: "End-of-day cash register",
        category: .reports,
        markdown: """
        # End-of-Day Cash Register (Z-Report)

        Close the day to lock the register and produce a Z-Report.

        ## Closing
        1. Tap **POS** → **Close Register**.
        2. Count the cash in the drawer and enter the amount.
        3. Tap **Close & Print Z-Report**.

        ## Reading the Z-Report
        The report shows: opening float, gross sales by tender type, refunds, net sales, and closing cash.

        ## Discrepancies
        Any short/over amount is flagged and can trigger a manager notification.
        """,
        tags: ["Z-report", "close", "register", "cash", "end of day"],
        relatedArticleIds: ["help.daily-reports"]
    )

    // MARK: - Daily Reports

    static let dailyReports = HelpArticle(
        id: "help.daily-reports",
        title: "Daily reports",
        category: .reports,
        markdown: """
        # Daily Reports

        Access summary and detailed reports from the **Reports** tab.

        ## Sales Summary
        Net sales, gross sales, average order value, and payment-method breakdown for any date range.

        ## Technician Performance
        Tickets completed, revenue per technician, and average completion time.

        ## Exporting
        Tap **Export** (top right) to generate a CSV or PDF. Use the share sheet to send via email or AirDrop.
        """,
        tags: ["report", "analytics", "export", "sales", "daily"],
        relatedArticleIds: ["help.end-of-day"]
    )

    // MARK: - SMS Messaging

    static let smsMessaging = HelpArticle(
        id: "help.sms-messaging",
        title: "SMS messaging",
        category: .communications,
        markdown: """
        # SMS Messaging

        Send and receive texts directly inside BizarreCRM.

        ## Sending a Message
        Open a customer → tap **SMS** → type and send.

        ## Inbound Messages
        A push notification is delivered when a customer replies. Tap to open the thread.

        ## Templates
        Go to **Settings** → **SMS** → **Templates** to create reusable message snippets.

        ## Campaigns
        Bulk SMS campaigns are under **Marketing** → **Campaigns**.
        """,
        tags: ["SMS", "text", "message", "twilio"],
        relatedArticleIds: ["help.customer-management"]
    )

    // MARK: - Appointment Scheduling

    static let appointmentScheduling = HelpArticle(
        id: "help.appointment-scheduling",
        title: "Appointment scheduling",
        category: .appointments,
        markdown: """
        # Appointment Scheduling

        Book appointments for repairs, fittings, consultations, or any service.

        ## Creating an Appointment
        1. Tap **Calendar** → **+**.
        2. Select a customer, service, staff member, and time slot.
        3. Tap **Save**. A confirmation SMS is sent automatically if enabled.

        ## Reminders
        BizarreCRM sends a 24-hour and a 1-hour reminder to the customer. Staff receive a push at the 1-hour mark.

        ## Rescheduling
        Open the appointment → tap **Reschedule** → pick a new time.
        """,
        tags: ["appointment", "calendar", "booking", "schedule"],
        relatedArticleIds: ["help.sms-messaging"]
    )

    // MARK: - Loyalty Program

    static let loyaltyProgram = HelpArticle(
        id: "help.loyalty-program",
        title: "Loyalty program",
        category: .loyalty,
        markdown: """
        # Loyalty Program

        Reward repeat customers with points and tiers.

        ## Enrolling a Customer
        Open a customer → tap **Loyalty** → **Enroll**.

        ## Earning Points
        Points are awarded automatically at checkout based on your shop's earn rate (e.g., 1 point per $1 spent).

        ## Redeeming Points
        At checkout tap **Redeem Points**. The customer's balance is displayed. Confirm the amount to discount.

        ## Tiers
        Configure tiers (Bronze, Silver, Gold) under **Settings** → **Loyalty**.
        """,
        tags: ["loyalty", "points", "reward", "membership"],
        relatedArticleIds: ["help.customer-management"]
    )
}
