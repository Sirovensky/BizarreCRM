# Electronics Setup Seed Enrichment Plan

This plan narrows setup enrichment to the current product center: electronics
repair shops that use tickets, estimates, parts, status updates, intake photos,
condition checks, and pickup workflows. It intentionally does not expand the CRM
into automotive, jewelry, appliance, furniture, HVAC, leather, or instrument
verticals yet.

The goal is to make the setup choice feel materially useful on day 1 without
requiring broad new schema. The preferred implementation path is seed data plus
existing/custom-field-style metadata, not a new generic asset system.

Preset shop types and custom device categories are separate concepts. The setup
wizard should stay curated, but the catalog/settings API should allow an admin
to create a custom category such as `vacuum-cleaners`; that category receives
generic condition checks and generic repair services until a richer industry
bundle exists.

## Concurrency Note

The main checkout is already heavily modified in setup, onboarding, seed, route,
pricing, and web UI files. There are also multiple Claude worktrees present.
Because of that, implementation is being kept in the separate
`codex/electronics-setup-seeds` worktree and should be merged only after the
active main-checkout work is reviewed. The branch currently owns setup
shop-type presets, onboarding/settings templates, service and condition seed
migrations, pricing copy, and device-model seed refreshes.

Observed hot areas in the main worktree:

- `packages/web/src/pages/setup/steps/StepShopType.tsx`
- `packages/web/src/pages/setup/wizardTypes.ts`
- `packages/web/src/api/endpoints.ts`
- `packages/web/src/pages/settings/components/SettingsTemplatePicker.tsx`
- `packages/server/src/routes/onboarding.routes.ts`
- `packages/server/src/db/device-models-seed.ts`
- `packages/server/src/db/migrations/162_dpi_seed_data_expansion.sql`
- `packages/server/src/routes/repairPricing.routes.ts`
- `TODO.md`

Merge strategy:

1. Keep `codex/electronics-setup-seeds` isolated while the active main checkout
   remains dirty.
2. Rebase this branch onto the then-current `main` when the other setup/pricing
   work is stable.
3. Resolve migration-number and setup/onboarding overlaps deliberately.
4. Re-run server build, web typecheck, and migration smoke tests after rebase.
5. Do not merge if main still has unreviewed edits in the same setup/onboarding
   files.

## Scope Decision

Keep setup focused on these six electronics presets:

1. Phone Repair
2. Phone + Tablet
3. Computer / IT Bench
4. Console / Gaming
5. TV / Consumer Electronics
6. Multi-device Electronics

Do not add these presets to the setup wizard yet:

- Auto repair
- Jewelry or mechanical watch repair
- Major appliance repair
- Furniture or upholstery repair
- Shoe or leather repair
- Musical instrument repair
- HVAC, plumbing, or field trades

Those verticals need different asset language, intake expectations, pricing
logic, compliance, scheduling, and operational workflows. Research into them is
useful as boundary-setting, but not as near-term product scope.

## Research Basis

The broader repair market is real, but electronics is the right near-term scope.

- BLS NAICS 811 defines repair and maintenance as restoring machinery,
  equipment, and other products to working order, with routine maintenance to
  prevent breakdown. It groups automotive, electronic/precision equipment,
  commercial machinery, and personal/household goods separately:
  https://www.bls.gov/iag/tgs/iag811.htm
- Census NAICS separates electronics repair from household goods repair. It
  describes computer repair under 811212 and communication equipment repair
  under 811213, while watches, jewelry, instruments, bicycles, and boats live
  in personal/household goods repair:
  https://www.census.gov/naics/resources/archives/sect81.html
- Apple iPhone repair manuals organize repair around diagnostics plus battery,
  charging/power, camera, display/image, speaker, ringer, and microphone issues:
  https://support.apple.com/en-ca/104900
- Samsung self-repair supports mobile, tablet, laptop, TV, audio, monitor, and
  home appliance products. For phones/tablets it explicitly references display,
  battery, back glass, charging port, speakers, SIM tray, side key, and volume
  key. For TVs/monitors/audio it references picture, power, Wi-Fi, sound, and
  remote control:
  https://news.samsung.com/us/samsung-self-repair-program-now-available-galaxy-customers
  https://news.samsung.com/us/samsung-adds-foldables-and-home-entertainment-products-to-self-repair-program
  https://www.samsung.com/us/support/self-repair/
- Google Pixel repair supports genuine parts and tools through iFixit for Pixel
  phones and tablets:
  https://support.google.com/pixelphone/answer/14257407
- Current model checks use official storefront/product pages first, then
  supplier catalog evidence. Apple currently lists iPhone 17 Pro/Pro Max,
  iPhone Air, iPhone 17, and iPhone 17e in its shop:
  https://www.apple.com/shop/buy-iphone
- Samsung currently lists the Galaxy S26/S26+/S26 Ultra series, Galaxy Z Fold7,
  Galaxy Z Flip7, Galaxy Z Flip7 FE, Galaxy S25 Edge, Galaxy S25 FE, and current
  A-series devices on official Samsung pages:
  https://www.samsung.com/us/smartphones/galaxy-s26/
  https://www.samsung.com/us/smartphones/galaxy-s26-ultra/
  https://www.samsung.com/us/smartphones/galaxy-z-fold7/
  https://www.samsung.com/us/smartphones/galaxy-z-flip7/
  https://www.samsung.com/us/smartphones/galaxy-z-flip7-fe/
  https://www.samsung.com/us/smartphones/galaxy-s25-edge/
  https://www.samsung.com/us/smartphones/galaxy-s25-fe/
  https://www.samsung.com/us/smartphones/galaxy-a16-5g/
- Google Store currently exposes Pixel 10, Pixel 10 Pro/Pro XL, Pixel 10 Pro
  Fold, Pixel 9a, Pixel 9 Pro Fold, Pixel 9, and Pixel 8a:
  https://store.google.com/us/product/pixel_10_pro_fold?hl=us
- Current tablet checks use Apple iPad shop/compare pages for iPad Pro M5,
  iPad Air M4, iPad A16, and iPad mini A17 Pro, plus Samsung tablet pages for
  Galaxy Tab S11/S11 Ultra:
  https://www.apple.com/shop/buy-ipad
  https://www.samsung.com/us/tablets/
- Microsoft Surface support makes replacement parts available for self-repair
  and links that repair flow to service guides and tools:
  https://support.microsoft.com/en-us/surface/how-to-get-service-or-repair-for-surface-b06da716-0763-65b3-e2f2-116d9e30f877
  https://blogs.windows.com/devices/2023/06/14/announcing-the-availability-of-consumer-replacement-components-for-surface-devices/
- uBreakiFix/Asurion service pages line up with the expected commercial repair
  catalog: smartphones cover screen, battery, charging port, camera, speaker,
  back glass, water damage, Wi-Fi/Bluetooth, and data transfer. PCs cover screen,
  water damage, hard drive, keyboard, battery, virus/spyware removal, data
  backup/recovery, driver update, software install, GPU upgrade, memory upgrade,
  and diagnostics:
  https://www.ubreakifix.com/repairs/smartphones
  https://www.ubreakifix.com/repairs/laptops-computers/pc
- Nintendo, PlayStation, and Steam Deck support/parts validate console repair as
  a distinct electronics track. Nintendo routes Joy-Con and Switch system
  repairs through support. PlayStation support covers console/system/controller
  troubleshooting. Valve/Steam Deck has official iFixit parts and guides for
  screens, thumbsticks, fans, and more:
  https://en-americas-support.nintendo.com/app/answers/detail/a_id/22517/~/repairing-your-nintendo-switch-system
  https://www.playstation.com/en-us/support/hardware/
  https://store.steampowered.com/news/posts/?enddate=1653325531&feed=steam_community_announcements
  https://www.ifixit.com/Parts/Steam_Deck
- Independent console repair menus repeatedly converge on HDMI ports, disc
  drives, overheating/fan/thermal service, storage, power, and controller drift:
  https://fixoid.com/portland-or/game-console-repair/
  https://phonerepairmore.com/xbox-repair/
- TV and monitor repair shops converge on power, no display/no signal,
  backlight, boards, HDMI/display inputs, sound, remote/IR, Wi-Fi, and panel
  economics:
  https://samsungparts.com/collections/television-parts
  https://www.computerlandberkeley.com/device-repair/monitor/
  https://technetronelectronics.com/

## Reference Data Handling

The attached real-shop screenshots are operational references only. They must
not be copied into the project as literal category names, status names, column
names, or price values.

Use them to learn the shape of the workflow:

- Repair shops need separate customer-facing and internal states.
- Parts procurement is not a single state; it has quote, order-needed,
  ordered, inbound, received, and queued-for-bench moments.
- Some component families have multiple quality/grade/supplier choices.
- Some line items are not normal repairs; they are cleaning, calibration,
  protection, small-component, or special-order work.
- Some outcomes are terminal and need careful customer messaging: cancelled,
  uneconomical to repair, abandoned, disposed, shipped, collected.

Implementation rule: re-name everything in BizarreCRM's own language. Do not
type data from the screenshots into seed files, migrations, tests, fixtures, or
docs except as this general warning.

Supplier catalog check: an isolated PhoneLCDParts scrape populated more than
9,000 rows in `/tmp/bizarre-crm-supplier-scrape.db` and confirmed current parts
coverage for iPhone 17, iPhone Air, iPhone 17e/16e, Galaxy S26/S25, Galaxy Z
Fold 7/Flip 7, and Pixel 10 family names. The scrape was run against a copied
database, not the dev DB.

## Current Repo Baseline

Visible seed counts in the current checkout:

| Category | Current visible model count |
| --- | ---: |
| Phone | 174 |
| Tablet | 39 |
| Laptop | 45 |
| Console | 19 |
| TV | 31 |

Relevant existing structures:

- `repair_services` already supports service categories by text slug.
- `repair_prices` maps `device_model_id` and `repair_service_id`.
- `condition_templates` and `condition_checks` already support category-level
  intake/QC templates.
- `customer_assets` exists but is electronics-shaped (`device_type`, `serial`,
  `imei`, `color`, `notes`).
- `ticket_devices` already carries core repair object fields: name, type, IMEI,
  serial, security code, color, network, service, price, status, notes,
  conditions, photos, parts, and checklist references.
- `custom_field_definitions` exists for `ticket`, `customer`, `inventory`, and
  `invoice` only in the route whitelist.

Near-term implementation should work inside those concepts. The only reasonable
field expansion is a setup seed for `custom_field_definitions` using existing
field types, plus a possible later whitelist addition for `ticket_device` if the
UI needs per-device custom fields. Avoid a new asset model for now.

Custom category behavior:

- `GET /catalog/categories` should return categories discovered from device
  models, condition templates, and repair services.
- `POST /catalog/categories` should create a slug from the admin-provided name,
  seed a default generic condition template, and seed basic generic services.
- Device model creation should preserve unknown category slugs instead of
  forcing them to `other`.
- Preset setup cards should not automatically appear for custom categories.

## Setup UI Shape

Use two or three groups on desktop to make options scannable without implying a
generic repair CRM.

Recommended grouping:

| Group | Cards |
| --- | --- |
| Mobile | Phone Repair, Phone + Tablet |
| Bench | Computer / IT Bench, Console / Gaming |
| Living Room | TV / Consumer Electronics, Multi-device Electronics |

Card counters should come from seed definitions, not hard-coded comments:

- Models available
- Services installed
- Intake fields installed
- Checklists installed

Avoid showing "thin" badges to users. If a preset is not rich enough, do not
ship it as a main setup option yet.

## Shared Seed Bundle Contract

The seed bundle should be explicit and versioned.

```ts
type ElectronicsSetupTemplate = {
  id: string;
  label: string;
  shortDescription: string;
  modelCategories: Array<'phone' | 'tablet' | 'laptop' | 'desktop' | 'console' | 'tv' | 'other'>;
  services: RepairServiceSeed[];
  conditionTemplates: ConditionTemplateSeed[];
  customFields: CustomFieldSeed[];
  smsTemplates: SmsTemplateSeed[];
  sampleTickets: SampleTicketSeed[];
  dynamicPricingSeeds: DynamicPricingSeed[];
  savedViews?: SavedTicketViewSeed[];
};
```

Implementation principle:

- Use additive `INSERT OR IGNORE` seed writes.
- Never overwrite owner-edited SMS templates, prices, statuses, custom fields,
  or checklists.
- Store a seed bundle version in audit details or onboarding state so future
  migrations can re-run only missing entries.
- Apply dynamic pricing seeds only to non-custom price rows and leave manual
  overrides intact.
- Keep field definitions optional unless there is a strong workflow reason to
  mark them required.

## Dynamic Pricing Seed Strategy

The setup seed should not behave like a static price sheet. BizarreCRM already
has the right direction: supplier catalog records, device compatibility,
`repair_price_grades`, supplier-cost refresh, profit recompute, margin alerts,
and auto-margin rules.

This module is still WIP, so setup should avoid brittle assumptions about the
final pricing workflow. Treat the fields below as intent that can be adapted by
the current pricing implementation, not as a hard dependency on one exact UI or
schema shape.

Use setup to seed pricing structure, not copied prices:

- Service-to-part-family mappings for supplier matching, such as display
  assembly, battery, charging connector, rear cover/housing, camera, audio,
  keyboard, fan, board, backlight, power board, and small components.
- Grade profiles with generic labels, such as economy, standard, premium, and
  original-grade. The final labels should be BizarreCRM language, not reference
  sheet column names.
- Labor fallback tiers by model age/popularity, used only when live supplier
  cost is missing or stale.
- Category-level auto-margin presets, rounding behavior, max nightly delta, and
  review thresholds.
- Quote-review flags for special-order parts, stale supplier costs, low margin,
  unusually high component cost, liquid damage, board-level work, and any repair
  where parts matching is uncertain.

Runtime pricing should come from supplier-aware rows:

- `repair_prices` stores the current labor suggestion and tier/default metadata.
- `repair_price_grades` links grade options to supplier catalog or inventory
  records and supports part-cost and labor overrides.
- Profit recompute updates supplier cost/profit metadata after supplier sync.
- Auto-margin may adjust suggested labor inside guardrails, while custom/manual
  prices stay protected.

If a supplier match is available, quote suggestions should combine the selected
grade's current supplier cost with labor/margin rules. If no supplier match is
available, setup should leave the row usable as a labor fallback but mark the
quote for owner review. Do not seed exact values from reference screenshots.

## Shared Workflow States

The earlier status list was too simple. A real repair counter needs enough
states to answer three questions quickly:

- Who owns the next move: shop, customer, supplier, courier, or technician?
- Is the device physically in the shop, inbound, outbound, or gone?
- Is the repair blocked by inspection, approval, parts, payment, QC, or pickup?

Recommended internal state groups:

| Group | Seeded state concept | Customer notified by default |
| --- | --- | --- |
| Intake | Intake logged | Yes |
| Intake | Queued for first inspection | No |
| Intake | Customer shipping inbound | Yes |
| Intake | Pickup from customer needs scheduling | Yes |
| Intake | Device received from shipment/pickup | Yes |
| Diagnosis | Diagnostic work active | Optional |
| Diagnosis | Findings recorded | Yes |
| Customer action | Estimate needs customer decision | Yes |
| Customer action | Customer question or missing info | Yes |
| Customer action | Customer approved work | Yes |
| Parts | Parts decision needed internally | No |
| Parts | Customer approval needed for special component | Yes |
| Parts | Supplier order pending | Optional |
| Parts | Supplier order placed | Yes |
| Parts | Ordered component delayed | Yes |
| Parts | Component received, awaiting bench slot | Optional |
| Bench | Repair work active | Optional |
| Bench | Repaired, awaiting QC | No |
| QC | QC passed | Optional |
| QC | QC failed, back to bench | No |
| Payment | Repair complete, balance due | Yes |
| Pickup | Ready for pickup | Yes |
| Pickup | Pickup reminder | Yes |
| Logistics | Return shipment being prepared | Yes |
| Logistics | Outbound handoff complete | Yes |
| Closed | Completed and collected | Yes |
| Closed | Completed and shipped | Yes |
| Closed | Cancelled / declined | Yes |
| Closed | Not economical to repair | Yes |
| Closed | Disposition completed | Optional |

These are concepts, not final labels. The implementation should name them in
BizarreCRM's voice and avoid copying any third-party status labels.

## Shared Customer Message Templates

Install customer-message templates around operational events, not generic
"marketing" moments. Each template should be short, clear, and easy for an
owner to edit.

Core templates for every electronics preset:

1. Intake received: confirms the item and ticket number.
2. Initial inspection queued: sets expectation that a technician has not yet
   begun diagnosis.
3. Diagnostic underway: used when a shop wants proactive transparency.
4. Diagnostic findings ready: asks the customer to review estimate or contact
   the shop.
5. Approval request: includes estimate total and clear approve/decline options.
6. Approval received: confirms work can proceed.
7. More information needed: asks for passcode, symptoms, account state, or
   permission needed to continue.
8. Parts approval needed: explains that a component choice or special-order part
   needs customer approval before ordering.
9. Parts ordered: confirms sourcing has started.
10. Parts delay: gives a plain delay update and keeps trust alive.
11. Parts received, queued for repair: tells the customer the job is moving
   again without promising same-hour completion.
12. Repair underway: optional message for longer jobs.
13. QC passed: optional message before pickup/payment notification.
14. QC issue found: customer-safe wording for a failed quality check when the
   delay matters.
15. Balance due: asks for payment or says payment is needed before pickup.
16. Ready for pickup: includes hours and pickup instructions.
17. Pickup reminder: sent after a configurable number of days.
18. Arrange pickup: used when the shop offers local pickup/drop-off.
19. Customer shipment request: asks the customer to ship the device in and
   include the ticket number.
20. Return shipment prepared: confirms shipping address before dispatch.
21. Return shipment sent: includes tracking placeholder.
22. Declined or cancelled: confirms the customer declined work or the shop
   cancelled the ticket.
23. Not economical to repair: explains the outcome politely and asks what the
   customer wants done with the item.
24. Disposal authorization request: asks for explicit consent before disposing
   or recycling.
25. Warranty return intake: confirms the device is being reviewed under repair
   warranty.
26. Warranty return outcome: explains whether the issue is covered.

Do not seed aggressive sales language. Repair customers usually want clarity,
timing, cost, data/privacy assurance, and pickup instructions.

## Shared Intake Field Strategy

Use custom-field-style seeds, not new schema, for now.

Preferred phase 1 entity type:

- `ticket`

Optional phase 2 entity type if needed:

- `ticket_device`

Recommended universal ticket-level fields:

| Field | Type | Applies to | Why |
| --- | --- | --- | --- |
| Data backup preference | select | phone, tablet, computer, console | Customer consent before resets or storage work |
| Passcode provided | select | phone, tablet, computer, console | Avoid storing secrets directly in generic notes |
| Accessories received | multiselect | all | Track chargers, cases, remotes, docks, cables |
| Rush requested | boolean | all | Affects queue and quote |
| Liquid damage observed | boolean | phone, tablet, laptop, console | Impacts warranty and estimate language |
| Prior repair attempted | boolean | all | Board-level risk and warranty exceptions |
| Customer-approved data risk | boolean | phone, tablet, computer, console | Resets, malware cleanup, drive work |
| Cosmetic damage noted | textarea | all | Intake protection |

Do not add fields like VIN, mileage, ring size, stone type, appliance location,
or refrigerant. Those belong to future verticals.

## Preset 1: Phone Repair

### Why It Belongs

Phone repair is the current strongest fit. The CRM already has phone models,
IMEI/serial fields, repair services, device history, pricing tiers, supplier
catalog work, photos, pre/post conditions, and warranty lookup patterns.

### Models

Use current `phone` models. Keep model coverage biased toward common iPhone,
Samsung Galaxy S/Note/Fold/Flip/A series, Google Pixel, Motorola, OnePlus, and
legacy LG devices already present.

Suggested model count target:

- Ship with current 174 phone models.
- Do not chase every SKU before the setup workflow is good.
- Keep current flagships refreshed from official product pages plus supplier
  catalog evidence.

### Service Catalog

Core service families to seed, using BizarreCRM naming rather than reference
sheet labels:

1. Initial diagnostic
2. Display assembly service
3. Battery service
4. Charging connector service
5. Rear housing or rear cover service
6. Camera module service
7. Camera lens cover service
8. Audio output service
9. Microphone service
10. Button or side-key service
11. Biometric diagnostic
12. Liquid exposure diagnostic and cleaning
13. Board-level diagnostic
14. Data transfer
15. Software restore or update
16. Activation or SIM/eSIM assistance
17. Post-repair calibration
18. Tray, bracket, adhesive, or small-component work
19. Port cleaning or debris removal
20. Protective film or accessory install
21. Other phone repair

Keep "unlocking" out of default services unless it is framed as activation help
or MDM/proof-of-ownership verification. Seed copy should never imply bypassing
ownership controls.

Reference-derived parts lesson:

- Treat major components, small components, cleaning, calibration, and accessory
  add-ons as different service families.
- Some devices need multiple display quality choices, but the seed should name
  these generically, such as economy, standard, premium, or original-grade,
  after a separate naming pass.
- Do not seed the exact spreadsheet column names or price values from the
  reference screenshots.

### Condition Checklist

Default phone intake checks:

1. Powers on
2. Display image
3. Touch response
4. Front glass cracked
5. Rear cover cracked
6. Frame bent
7. Battery health recorded
8. Charging port tested
9. Wireless charging tested if supported
10. Customer-facing camera
11. Main camera
12. Face ID / Touch ID
13. Earpiece speaker
14. Loudspeaker
15. Microphone
16. Volume buttons
17. Power button
18. Mute/action switch
19. Wi-Fi
20. Bluetooth
21. Cellular signal / SIM read
22. Liquid contact indicator checked
23. Prior repair signs
24. Photos taken

### Custom Fields

Ticket-level fields to seed:

| Field | Type | Options |
| --- | --- | --- |
| Device lock state | select | Unknown, Unlocked, Passcode provided, Repair mode enabled, Customer must unlock |
| Data backup preference | select | Not asked, Customer says backed up, Backup requested, Data not important |
| Battery health percent | number | None |
| Carrier / network | text | None |
| Protection plan / warranty source | select | None, AppleCare, Samsung Care, Carrier, Third party, Unknown |
| Case or screen protector received | boolean | None |
| SIM/eSIM concern | boolean | None |

### Dynamic Pricing Defaults

Phone setup should seed the richest dynamic pricing structure because phones are
where supplier catalogs and grade choices matter most.

- Seed part-family aliases for display assemblies, batteries, charging
  connectors, rear cover/housing work, camera modules, camera lens covers,
  audio parts, buttons, trays, adhesives, and small components.
- Seed generic grade profiles for display and major component work. Use
  BizarreCRM labels, not supplier-sheet labels.
- Seed labor fallback tiers for flagship, mainstream, and legacy devices, but
  treat them as fallback labor when supplier cost is absent or stale.
- Enable supplier-cost freshness warnings and low-margin review flags for major
  component work.
- Keep diagnostics, liquid exposure, cleaning, calibration, data transfer, and
  board-level work as labor/service lines that can convert into approved repair
  work after estimate approval.

The quote path should prefer live supplier data through `repair_price_grades`
and compatibility matching. If the supplier match is missing, the row remains
usable but the estimate should be flagged for owner review.

### Sample Tickets

Seed examples:

1. iPhone 13 - cracked display, Face ID check required, customer approved
   aftermarket screen.
2. iPhone 15 Pro - back glass cracked, wireless charging works, parts ordered.
3. Galaxy S22 Ultra - intermittent USB-C charging, port debris first, quote
   pending.
4. Pixel 7a - battery swelling concern, safety intake, do not power on.
5. iPhone SE 2nd Gen - battery health 74 percent, same-day battery.
6. Galaxy A14 - water exposure, no power, board diagnostic declined.

### What Not To Add Yet

- Carrier unlock workflows
- MDM bypass workflows
- Insurance claim adjudication
- Mail-in repair logistics
- Buyback/trade-in grading beyond simple condition checks

## Preset 2: Phone + Tablet

### Why It Belongs

Many phone shops accept iPads, Galaxy Tabs, Surface tablets, and kids/school
tablets without becoming full computer shops. The workflow is nearly identical
to phone repair: intake, photos, screen/battery/port services, parts, estimate,
repair, QC, pickup.

### Models

Use current phone and tablet model coverage:

- Phone: 174 visible models
- Tablet: 39 visible models
- Combined target: 213 models

Tablet coverage should emphasize iPad, iPad Air, iPad mini, iPad Pro, Galaxy
Tab S/A series, and Surface Pro where the existing category treats Surface as a
tablet.

### Service Catalog

Install all Phone Repair services plus tablet-specific variants:

1. Tablet screen assembly
2. Tablet glass/digitizer only
3. Tablet LCD/OLED replacement
4. Tablet battery
5. Tablet charging port
6. Tablet camera
7. Tablet button repair
8. Tablet speaker
9. Tablet microphone
10. Tablet housing/frame repair
11. Tablet water diagnostic
12. Tablet software restore
13. Pencil/stylus pairing help
14. Keyboard case diagnostic
15. Tablet MDM/profile verification
16. Other tablet repair

Avoid making tablets a separate card from phones unless a shop explicitly wants
tablet-only. The real-world overlap is high.

### Condition Checklist

Use the phone checklist plus:

1. Stylus/pencil pairs
2. Keyboard/case connector tested
3. Touch dead zones checked
4. Rotation sensor checked
5. Home button or top button checked
6. Charging cable angle sensitivity checked
7. MDM/school profile visible
8. Stand/case damage noted

### Custom Fields

| Field | Type | Options |
| --- | --- | --- |
| Tablet ownership type | select | Personal, School, Business, Unknown |
| MDM or school profile present | boolean | None |
| Pencil/stylus included | boolean | None |
| Keyboard case included | boolean | None |
| Charger included | boolean | None |
| Child account / parental PIN concern | boolean | None |

### Dynamic Pricing Defaults

Tablet pricing should inherit the phone dynamic model but use tablet-specific
review rules.

- Map display assembly, glass/digitizer, battery, charging connector, keyboard
  connector, and housing/frame work to supplier-search families.
- Keep adhesive-heavy display work in a higher labor fallback profile than
  phones, because cleanup and frame risk are material.
- Flag bent frames, lifted displays, and school/MDM ownership as quote-review
  conditions.
- Treat software restore, activation help, and MDM verification as labor/service
  lines unless a paid escalation is approved.

Live supplier cost should drive the selected grade whenever matched. Fallback
labor is only a starting point for rows with missing or stale supplier data.

### Sample Tickets

1. iPad 9th Gen - cracked digitizer, LCD tests good, customer wants budget
   glass-only repair.
2. iPad Pro 11 - bent frame and display lift, quote requires frame risk note.
3. Galaxy Tab S8 - not charging, cable tested, port replacement likely.
4. Surface Pro 8 - cracked screen, keyboard included, BitLocker concern noted.
5. iPad mini 6 - school device with MDM profile, approval required before reset.

### What Not To Add Yet

- School district contract workflows
- Device fleet management
- Rental tablet inventory
- Mail-in classroom repair batching

## Preset 3: Computer / IT Bench

### Why It Belongs

Computer repair shares the same ticket and estimate model but has different
privacy and data-risk expectations. It should be a separate setup option from
phone repair because diagnostics, backup consent, passwords, malware, OS work,
and storage decisions shape the workflow.

### Models

Use current `laptop` model coverage for known devices:

- 45 visible laptop models

Do not block desktop repair on a complete desktop model library. For now, allow
free-text device names like "Custom Gaming PC", "Dell OptiPlex desktop", or
"All-in-one PC". If desktop models are later added to `device_models`, that can
be a catalog task, not a setup blocker.

### Service Catalog

Core bench services:

1. Computer diagnostic
2. No-boot diagnostic
3. OS reinstall / repair
4. Virus and malware removal
5. Performance tune-up
6. Data backup
7. Data transfer
8. Data recovery triage
9. SSD/HDD replacement
10. RAM upgrade
11. Laptop screen replacement
12. Laptop battery replacement
13. Keyboard replacement
14. Trackpad replacement
15. Charging port / DC jack repair
16. Hinge repair
17. Fan replacement
18. Thermal paste / overheating service
19. Motherboard diagnostic
20. GPU diagnostic / replacement
21. Power supply replacement
22. Driver update
23. Software install
24. New computer setup
25. Custom PC build / rebuild
26. Other computer repair

Keep recurring MSP, endpoint management, and managed backup outside setup. Those
are different products.

### Condition Checklist

1. Powers on
2. POST / boot chime
3. Display image
4. Keyboard
5. Trackpad / mouse
6. Webcam
7. Speakers
8. Microphone
9. USB ports
10. USB-C / charging port
11. Wi-Fi
12. Bluetooth
13. Battery status
14. Charger tested
15. Storage SMART status
16. Liquid damage signs
17. Hinge/case damage
18. Fan noise / overheating
19. BitLocker/FileVault/encryption noted
20. Customer data risk acknowledged
21. Photos taken

### Custom Fields

| Field | Type | Options |
| --- | --- | --- |
| Admin password status | select | Not provided, Provided verbally, Customer will enter, Not needed |
| Data backup consent | select | Not asked, Approved, Declined, Customer says backed up |
| Encryption status | select | Unknown, BitLocker, FileVault, Other, None |
| Charger included | boolean | None |
| Storage device returned to customer | boolean | None |
| Business-critical device | boolean | None |
| OS | select | Windows, macOS, ChromeOS, Linux, Unknown |
| Malware symptoms | textarea | None |

### Dynamic Pricing Defaults

Computer work should mix service labor lines with supplier-aware parts where a
catalog match exists.

- Keep diagnostic, malware cleanup, OS reinstall, data backup, data recovery
  triage, password/account assistance, tune-up, and custom-build work as labor
  service lines.
- Map laptop display, battery, keyboard/top case, charging connector/DC jack,
  hinge, fan, thermal assembly, RAM, storage, GPU, and power supply work to part
  families.
- Mark storage/data work with explicit data-risk consent and quote-review flags.
- Use model/tier fallbacks for common laptops, but keep desktops and custom PCs
  review-first unless a compatible part is selected.

Supplier matches should feed component cost and margin suggestions. Labor-only
fallbacks exist for service work and unmatched parts, not because parts pricing
is out of scope.

### Sample Tickets

1. Dell XPS 15 - no boot, SMART warnings, customer approved SSD replacement and
   data transfer.
2. MacBook Air M1 - cracked display, FileVault enabled, customer will enter
   password at pickup.
3. HP Pavilion - malware pop-ups, data backup approved, tune-up package quoted.
4. Custom Gaming PC - GPU artifacts under load, customer brought power cable.
5. Lenovo ThinkPad - broken hinge and keyboard, parts ordered.
6. Chromebook - school profile present, no reset without owner approval.

### What Not To Add Yet

- Managed IT contracts
- Remote monitoring agents
- Domain controller/server administration
- Long-running subscription support
- Cybersecurity incident response

## Preset 4: Console / Gaming

### Why It Belongs

Console repair is a repair-shop workflow with a distinct bench pattern: HDMI
ports, overheating, disc drives, storage, controller drift, USB-C charging, and
handheld screens. It should not be buried inside generic computer repair because
the intake fields and services are different.

### Models

Use current console coverage:

- 19 visible console models

Expected model families:

- PlayStation 5, PlayStation 4 variants
- Xbox Series X/S, Xbox One variants
- Nintendo Switch, Switch OLED, Switch Lite
- Steam Deck / gaming handhelds where available
- Controllers as service objects, even if not modeled as `device_models`

### Service Catalog

Core services:

1. Console diagnostic
2. HDMI port replacement
3. USB-C / charging port repair
4. Power supply repair
5. No-power diagnostic
6. Disc drive repair
7. Disc eject mechanism
8. Hard drive / SSD replacement
9. Storage upgrade
10. Fan replacement
11. Thermal paste service
12. Overheating deep clean
13. Motherboard diagnostic
14. Wi-Fi / Bluetooth repair
15. Controller joystick drift repair
16. Controller button repair
17. Controller charging port repair
18. Controller battery replacement
19. Switch screen replacement
20. Switch game card reader
21. Joy-Con rail repair
22. Firmware/software reset
23. Save data transfer assist
24. Retro console basic solder repair
25. Other console repair

### Condition Checklist

1. Powers on
2. Video output
3. HDMI port physical condition
4. USB ports
5. Disc reads
6. Disc ejects
7. Fan spins
8. Overheating symptom reproduced
9. Controller pairs
10. Wi-Fi connects
11. Bluetooth connects
12. Storage detected
13. Game card slot tested if handheld
14. Dock tested if Switch
15. Power supply/cable included
16. Disc or game card inside
17. Account lock / parental PIN noted
18. Save data risk acknowledged
19. Photos taken

### Custom Fields

| Field | Type | Options |
| --- | --- | --- |
| Power cable included | boolean | None |
| Controller included | boolean | None |
| HDMI cable included | boolean | None |
| Dock included | boolean | None |
| Disc/game card inside | boolean | None |
| Account or parental PIN concern | boolean | None |
| Save data consent | select | Not asked, Preserve required, Reset approved, Data not important |
| Overheating symptom | textarea | None |

### Dynamic Pricing Defaults

Console pricing should start from a compact repair menu but still use supplier
matching for repeatable parts.

- Map HDMI/USB-C connectors, disc-drive assemblies, fans, thermal materials,
  power modules, storage, handheld displays, controller sticks, controller
  buttons, and controller batteries to part families.
- Keep diagnostic, deep cleaning, thermal service, firmware/software recovery,
  and motherboard triage as labor/service lines.
- Flag soldered-port work, board-level work, save-data risk, parental/account
  locks, and special-order parts for review.

When supplier cost is available, grade/part selections should drive quote
suggestions. Missing supplier matches should fall back to labor plus manual
parts review.

### Sample Tickets

1. PS5 - no signal, HDMI port visibly damaged, same-day quote pending.
2. Xbox Series X - overheating after 20 minutes, deep clean and thermal service.
3. Nintendo Switch OLED - USB-C port bent, dock included, save data preserve.
4. DualSense controller - left stick drift, customer wants both sticks tested.
5. PS4 - disc drive grinding and eject failure, disc inside at intake.
6. Steam Deck - right thumbstick damage, iFixit-style part ordered.

### What Not To Add Yet

- Game resale inventory
- Modchip workflows
- Account recovery services
- Warranty adjudication for manufacturers
- Large retro restoration catalog

## Preset 5: TV / Consumer Electronics

### Why It Belongs

TV, monitor, and home entertainment repair is electronics repair, but it is not
the same workflow as mobile repair. Shops need screen size, remote/stand/cable
tracking, pickup/delivery notes, panel economics, and board/backlight diagnosis.

### Models

Use current TV model coverage:

- 31 visible TV model/intake families

Keep the first release focused on TV and monitor-like devices. Audio gear can be
represented by service categories, not a large model library, until the workflow
is proven.

### Service Catalog

Core services:

1. TV diagnostic
2. No-power diagnostic
3. Backlight repair
4. Power supply board
5. Main board
6. T-Con / timing board
7. HDMI port repair
8. Speaker/audio repair
9. Wi-Fi / smart feature repair
10. Remote / IR board repair
11. Firmware / smart reset
12. Panel assessment
13. Monitor diagnostic
14. Monitor backlight / no display
15. Monitor input port repair
16. Projector bulb / lamp replacement
17. Projector HDMI/input diagnostic
18. Soundbar diagnostic
19. Receiver diagnostic
20. Other consumer electronics repair

Panel replacement should be seeded as "assessment" rather than a normal repair
because panel work is often not cost-effective. This protects quote quality.

### Condition Checklist

1. Model tag photo
2. Screen cracked
3. Panel lines / image artifacts
4. Backlight visible
5. Sound works
6. Powers on
7. Standby light behavior
8. Remote included
9. Stand/feet included
10. Power cord included
11. HDMI inputs tested
12. Wi-Fi/smart menu tested
13. Buttons/joystick tested
14. Prior board replacement signs
15. Wall mount status noted
16. Pickup/delivery/remount note
17. Panel economics explained if cracked
18. Photos taken

### Custom Fields

| Field | Type | Options |
| --- | --- | --- |
| Screen size | number | None |
| Product type | select | TV, Monitor, Projector, Soundbar, Receiver, Other |
| Remote included | boolean | None |
| Stand included | boolean | None |
| Wall mounted | boolean | None |
| Pickup/delivery needed | boolean | None |
| Input/source issue | select | All inputs, HDMI only, Antenna, App/smart TV, Unknown |
| Panel cracked | boolean | None |

### Dynamic Pricing Defaults

TV and monitor pricing should be review-heavy because panel economics can flip
a job from repairable to not economical quickly.

- Map backlight strips, power boards, main boards, timing/control boards,
  input boards, speakers, remotes, projector lamps, and monitor input parts to
  supplier-search families.
- Keep diagnostic, firmware reset, input/source setup, panel assessment, pickup
  intake, and remount notes as labor/service lines.
- Flag cracked panels, OLED panel replacement, very large screens, pickup or
  delivery logistics, and stale supplier cost for review.

Use supplier data for boards and lamps when available. Panel replacement should
default to estimate review rather than an automatic price suggestion.

### Sample Tickets

1. Samsung 55 inch LED - sound but no picture, flashlight test suggests
   backlight failure.
2. LG OLED 65 inch - no power, stand and remote included, diagnostic pending.
3. TCL 50 inch - HDMI 1 damaged, other inputs work, port quote needed.
4. Vizio 65 inch - Wi-Fi menu fails, firmware reset attempted.
5. Dell monitor - USB-C input intermittent, no panel cracks.
6. Soundbar - no audio over HDMI ARC, remote included.

### What Not To Add Yet

- Full in-home dispatch optimization
- Installer quoting
- Wall-mount project management
- Home automation integration
- Major appliance repair

## Preset 6: Multi-device Electronics

### Why It Belongs

This preset is for shops that take phones, tablets, computers, consoles, and TVs
but do not want to curate separate catalogs before going live. It should install
a sensible union of the other electronics presets, not a generic "everything"
mode.

### Models

Use all current electronics models:

- Phone: 174
- Tablet: 39
- Laptop: 45
- Console: 19
- TV: 31
- Combined visible target: 308 models

### Service Catalog

Install a curated union:

- All core phone services
- All core tablet services
- Computer diagnostics, OS/malware/data/storage/screen/battery/keyboard/hinge
- Console HDMI/disc/fan/storage/controller/Switch services
- TV diagnostic/backlight/power/main/T-Con/HDMI/audio/smart reset

Do not simply install every service forever. Mark advanced/niche services as
inactive or lower sort order if needed.

### Condition Templates

Install category-specific condition templates for:

1. Phone
2. Tablet
3. Laptop/computer
4. Console
5. TV/monitor
6. Other electronics

The intake UI should select the template based on device type. Do not use one
massive universal checklist.

### Custom Fields

Use the smallest universal set:

| Field | Type | Options |
| --- | --- | --- |
| Accessories received | multiselect | Charger, Power cable, Remote, Controller, Dock, Case, Keyboard, Stylus, HDMI cable, Other |
| Passcode/password status | select | Not needed, Customer will enter, Provided, Unknown |
| Data risk consent | select | Not needed, Preserve data, Reset approved, Backup requested |
| Liquid damage observed | boolean | None |
| Prior repair attempted | boolean | None |
| Rush requested | boolean | None |

Then install category-specific optional fields, but keep them hidden or grouped
behind the selected device type if the UI supports that later.

### Dynamic Pricing Defaults

Multi-device shops should install the same dynamic profiles as the individual
electronics categories, then use the selected device category to choose the
right part-family aliases, grade options, review rules, and labor fallbacks.

The purpose is day-1 quote safety: live supplier cost when available, protected
manual overrides, and clear review flags when the system is uncertain.

### Sample Tickets

Seed a balanced demo board:

1. iPhone screen repair - approved, in repair.
2. iPad charging port - waiting parts.
3. MacBook no boot - diagnostic.
4. Gaming PC overheating - estimate sent.
5. PS5 HDMI port - waiting approval.
6. Switch Joy-Con drift - ready for pickup.
7. Samsung TV no picture - diagnostic.
8. Monitor USB-C input - in repair.

### Saved Views

Multi-device shops need filtering more than single-category shops.

Suggested saved views:

1. Mobile Bench
2. Computer Bench
3. Console Bench
4. TV / Large Items
5. Waiting Parts
6. Ready Today
7. Data Risk / Backup Needed

### What Not To Add Yet

- Non-electronics repair objects
- Generic asset-type builder
- Industry-specific vertical onboarding outside electronics
- Overloaded dashboards with dozens of unrelated workflows

## Implementation Plan

### Phase 1: Planning-safe seed definitions

Files likely involved once the active workspace is safe:

- New: `packages/server/src/services/onboarding/electronicsSetupTemplates.ts`
- Edit: `packages/server/src/routes/onboarding.routes.ts`
- Edit: `packages/web/src/api/endpoints.ts`
- Edit: `packages/web/src/pages/setup/steps/StepShopType.tsx`
- Edit: `packages/web/src/pages/settings/components/SettingsTemplatePicker.tsx`
- Optional edit: `packages/server/src/routes/customFields.routes.ts` if adding
  `ticket_device` custom fields

Work:

1. Define the six templates as static data.
2. Add a server helper that installs services, checklists, SMS templates, custom
   fields, pricing defaults, saved views, and sample tickets idempotently.
3. Keep installation transactional where possible.
4. Return counts to the frontend after install.
5. Add audit details: template id, version, counts installed, counts skipped.

### Phase 2: Setup UI

1. Replace three cards with grouped electronics cards.
2. Show real counts from template metadata.
3. Keep "Skip" available.
4. Preserve non-blocking behavior if install fails.
5. Avoid "thin" badges by gating cards that do not meet seed quality.

### Phase 3: Settings Template Picker

1. Mirror the six setup presets.
2. Add confirm copy: "Installs missing starter content only. Existing custom
   data is kept."
3. Show current installed template and version.
4. Add "Preview contents" details before install if practical.

### Phase 4: Tests

Add tests that enforce seed quality:

1. Every visible setup template has at least 10 active services.
2. Every visible setup template has at least one condition template.
3. Every visible setup template installs at least 5 SMS templates.
4. Every visible setup template installs at least 3 custom-field-style intake
   fields.
5. `set-shop-type` is idempotent.
6. Re-running a template does not overwrite edited templates or custom prices.
7. Frontend card counts match backend metadata.

### Phase 5: Optional Per-device Custom Fields

Only do this if ticket-level fields feel too blunt for multi-device tickets.

Minimal code change:

- Add `ticket_device` to `VALID_ENTITY_TYPES`.
- Add `ticket_device: 'ticket_devices'` to `ENTITY_TABLES`.
- Use the existing `custom_field_definitions` and `custom_field_values` tables.

Do not create a new custom fields system.

## Acceptance Criteria

The setup enrichment is review-ready when:

1. The setup wizard presents six electronics-only presets.
2. Each preset has a coherent service catalog that maps to actual repair shop
   work.
3. Each preset has category-specific condition checks.
4. Each preset has useful intake fields without broad schema expansion.
5. Each preset has SMS templates that match repair workflow moments.
6. Each preset has believable sample tickets.
7. Card counts are generated from seed metadata.
8. Install is idempotent and non-destructive.
9. No non-electronics verticals are added to the wizard.
10. Tests prevent another "thin" setup card from shipping.

## Deferred Verticals Parking Lot

Keep these as future research notes only:

- Auto Repair: needs VIN, mileage, license plate, labor guide concepts, bay
  scheduling, road-test authorization, and parts compatibility.
- Jewelry / Watch: needs metal, stone, ring size, declared value, appraisal,
  precious goods custody, and different liability language.
- Appliance Repair: needs field dispatch, appliance location, gas/electric,
  property access, and household appointment windows.
- Furniture / Upholstery: needs dimensions, fabric, material sourcing, pickup
  logistics, and restoration estimates.
- Shoe / Leather: needs item material, color matching, stitching/sole/heel
  workflows, and small-ticket counter service.
- Musical Instrument: needs school/rental context, instrument family, case/bow
  accessories, concert deadlines, and specialized repair checklists.

These are valuable later, but they should not influence the core electronics
setup model until the electronics workflow is excellent.
