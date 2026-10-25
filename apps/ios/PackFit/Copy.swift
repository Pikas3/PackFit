import Foundation

enum Copy {
    enum App {
        static let name = "Snugly"
        static let tagline = "Scan it. Pack it. Fly home under 23 kg."
    }

    enum Onboarding {
        static let skip = "Skip"
        static let next = "Next"
        static let done = "Get started"
        static let s1Title = "Measure with your phone"
        static let s1Body = "Snap one photo of your things with a credit card beside them. The card sets the scale."
        static let s2Title = "See the packing plan in 3D"
        static let s2Body = "Step through exactly where each item goes in your bag."
        static let s3Title = "Rules with sources"
        static let s3Body = "Flags link to TSA, airline, or customs pages. Guidance only — not the final word."
    }

    enum Trip {
        static let title = "Your trip"
        static let continueButton = "Continue to bag / scan"
        static let cancel = "Cancel"
        static let keyboardDone = "Done"
        static let flightHeader = "Find your flight"
        static let flightIntro = "Enter the airline code and flight number. We’ll fill origin, destination, weather, and packing rules for that route."
        static let airlineField = "Airline (IATA, e.g. UA)"
        static let flightNumberField = "Flight number (e.g. 88)"
        static let lookupFlight = "Look up flight"
        static let lookingUp = "Looking up flight…"
        static let flightFound = "Flight found"
        static let useThisFlight = "Use this flight"
        static let needFlightFields = "Enter both an airline code and a flight number."
        static let flightNotFound = "Couldn’t find that flight. Try a demo like UA 88."
        static let demoFlightsHint = "Demo flights (offline): UA 88 SFO→DEL, BA 178 JFK→LHR, AS 204 SEA→KEF, DL 188 LAX→ICN, AA 100 SFO→LAX."
        static let loadingDestination = "Loading destination weather and tips…"
        static let weatherHeader = "Weather at destination"
        static func weatherAtDestination(_ code: String) -> String { "Forecast for \(code) only — after your flight is selected." }
        static let routeRulesHeader = "What you can / can’t bring"
        static func internationalRoute(_ from: String, _ to: String) -> String { "International: \(from) → \(to). Destination customs apply." }
        static let nightsField = "Nights"
        static let bagField = "Bag for this trip"
        static let checkedBag = "Checked"
        static let carryOnBag = "Carry-on"
        static let activitiesHeader = "Activities"
        static let activityOther = "Other activity"
        static let datesField = "Flight dates"
        static let addDates = "Add depart and return dates"
        static let departLabel = "Depart"
        static let returnLabel = "Return"
        static let addDate = "Add date"
        static let pickReturn = "add return"
        static let pickDepartHint = "Tap your depart day"
        static let pickReturnHint = "Now tap your return day"
        static let clearDates = "Clear"
        static let doneDates = "Done"
        static let previousMonth = "Previous month"
        static let nextMonth = "Next month"
        static let showCalendarHint = "Opens the calendar"
        static let hideCalendarHint = "Closes the calendar"
        static let needReturnDate = "Pick a return day too, or clear the dates."
        static func nights(_ n: Int) -> String { n == 1 ? "1 night" : "\(n) nights" }
        static let suggestionsCTA = "Packing suggestions"
        static let beforeYouGoCTA = "Before you go"
        static let suggestionsTitle = "Suggestions"
        static let suggestionsEmpty = "No new suggestions — you’ve already added these, or none came back."
        static let loadingSuggestions = "Loading suggestions…"
        static let continueScan = "Scan items"
        static let essential = "Essential"
        static let accept = "Add"
        static func addCount(_ n: Int) -> String { n <= 1 ? "Add" : "Add \(n)" }
        static func howMany(_ name: String) -> String { "How many \(name) to add" }
        static func suggestionsCaption(_ n: Int) -> String { n == 1 ? "1 idea for this trip" : "\(n) ideas for this trip" }
        static func suggestionSize(dims: [Double], kg: Double, count: Int) -> String {
            let size = dims.count == 3 ? String(format: "%.0f×%.0f×%.0f cm", dims[0], dims[1], dims[2]) : "Size unknown"
            if count > 1 {
                return String(format: "%@ · %.2f kg each · %.1f kg total · estimated", size, kg, kg * Double(count))
            }
            return String(format: "%@ · %.2f kg · estimated", size, kg)
        }
        static let beforeYouGoTitle = "Before you go"
        static let beforeYouGoEmpty = "No destination tips yet. Continue offline with the sample list."
        static func destinationCountry(_ code: String) -> String { "Destination country: \(code)" }
        static let packThese = "Pack these"
        static let leaveOrDeclare = "Leave behind or declare"
        static let medsFood = "Medication & food"
        static let packedWarnings = "Packed items to review"
        static let weightWarning = "Weight"
        static let sourceLink = "Source"
    }

    enum Bag {
        static let title = "Your bag"
        static let presets = "Presets"
        static let custom = "Custom"
        static let measureCamera = "Measure with the camera"
        static let measureManual = "Enter dimensions"
        static let wheelsPrompt = "Where are the wheels?"
        static let wheelsBack = "Back"
        static let wheelsBottom = "Bottom"
        static let shellPrompt = "How does your suitcase open?"
        static let shellMessage = "Some bags are one open shell. Others zip into two sides (base and lid)."
        static let shellSingle = "One main cavity"
        static let shellTwoSided = "Two sides (zipper)"
        static let continueItems = "Add items"
        static let weightLimit = "Weight limit (kg)"
    }

    enum Items {
        static let title = "Items"
        static let scan = "Scan item"
        static let scanMore = "Scan more items"
        static let needFlight = "Add your flight to pack"
        static let needBag = "Choose your bag to pack"
        static func summary(_ count: Int, kg: Double) -> String {
            String(format: "%d item%@ · %.1f kg", count, count == 1 ? "" : "s", kg)
        }
        static let pack = "Pack bag"
        static let empty = "No items yet. Scan three things from the pile."
        static let emptyAction = "Scan an item"
        static let delete = "Delete"
        static let flagsHint = "Open flags for guidance with source links."
        static let reviewFlags = "Review all flags"
        static let confirmTitle = "Confirm item"
        static let confirmIdentity = "We’re not sure what this is"
        static let confirmIdentityBody = "Low confidence identification. Confirm the name before packing."
        static let confirmYes = "Looks right"
        static let confirmEdit = "Edit name"
    }

    enum Inventory {
        static let title = "Photo inventory"
        static let entry = "Snap the pile"
        static let hint = "Put a credit card flat on the floor next to your things. Hold the phone at about 45°, with everything in the frame. Tap the card if it is hard to lock."
        static let tapToFocus = "Looking for the card here…"
        static let cardSeen = "Card found. Take the photo."
        static let capture = "Take photo"
        static let identifying = "Finding everything in the photo… usually 5–15 seconds."
        static let privacy = "The photo goes to our server and Claude, and is not stored."
        static let simulator = "No camera in the simulator. Tap Take photo to use sample items."
        static let cameraUnavailable = "Camera unavailable. Check camera access in Settings."
        static let failed = "We couldn't identify anything just now. Try again, or add items by hand."
        static let nothingFound = "Nothing to pack found in that photo. Move closer and try again."
        static let sampleData = "Sample data: these items are not from your photo. Claude is not connected (mock mode or no API key on the server)."
        static let noCard = "No credit card found in the photo. Lay a card flat next to your things, fully in view, and try again."
        static let useEstimates = "Use rough estimates"
        static let measuredNote = "Sizes measured against your card. Tap an item to fix it."
        static let steepNote = "Heights are guesses: the photo looks straight down. Tilt the phone to about 45° for heights."
        static let tryAgain = "Try again"
        static let scanMore = "Scan more"
        static let estimateNote = "Sizes are guesses from the photo. Tap an item to fix it."
        static let duplicate = "Seen in an earlier photo"
        static let included = "Will be added"
        static let excluded = "Won't be added"
        static func found(_ n: Int) -> String { n == 1 ? "1 thing found" : "\(n) things found" }
        static func review(_ n: Int) -> String { "Review \(n) found" }
        static func add(_ n: Int) -> String { n == 1 ? "Add 1 item" : "Add \(n) items" }
    }

    enum Scan {
        static let looksRight = "Looks right"
        static let checkSize = "Check the size"
        static let pleaseMeasure = "Please measure"
        static let measuredDepth = "Measured with depth"
        static let measuredManual = "Entered manually"
        static let measuredReference = "Scaled from credit card"
        static let estimatedFromPhoto = "Estimated from photo"
    }

    enum Viewer {
        static let title = "Packing plan"
        static let play = "Play"
        static let pause = "Pause"
        static let peel = "Peel layers"
        static let step = "Step"
        static let fill = "Fill"
        static let weight = "Weight"
        static let unplaced = "Didn’t fit"
        static let openRules = "Rules"
        static let tooLarge = "Bigger than the bag in every direction. Check its size, or carry it."
        static let fragileInTheWay = "The only room left is on top of a fragile item. Pack the fragile item elsewhere, or mark this one soft."
        static let noRoom = "No space left. Remove something or use a bigger bag."
        static let invalidSize = "Its size is missing. Tap to enter it."
    }

    enum Rules {
        static let title = "Travel rules"
        static let stale = "Some sources are older than 30 days. Double-check before you fly."
        static let empty = "No flags for these items on this trip."
        static let guidance = "Guidance only — not authority."
        static let verifiedPrefix = "Verified"
        static let daysAgo = "days ago"
    }

    enum Tabs {
        static let home = "Home"
        static let results = "Results"
        static let plan = "Plan"
    }

    enum Home {
        static let greeting = "Hi there, traveler"
        static let title = "Let’s pack smarter"
        static let nextTrip = "Next trip"
        static let noTrip = "Where to next?"
        static let noTripBody = "Add your flight below and we’ll check the rules for your route."
        static let tripBody = "Snap your stuff and your bag. We’ll play packing Tetris for you."
        static func inDays(_ place: String, _ days: Int) -> String {
            switch days {
            case 0: "\(place) today"
            case 1: "\(place) tomorrow"
            default: "\(place) in \(days) days"
            }
        }
        static func nights(_ place: String, _ n: Int) -> String { "\(place) · \(n) nights" }
        static let snapTitle = "Snap your stuff"
        static let snapCaption = "Lay everything out on your bed in good light"
        static let itemsTile = "Your items"
        static let itemsEmpty = "Snap the pile, or scan items one by one."
        static func itemsFound(_ n: Int) -> String { n == 1 ? "1 item found" : "\(n) items found" }
        static let addPhoto = "Add photo"
        static let bagTile = "Your bag"
        static let bagEmpty = "Pick a preset or measure it. Open it fully!"
        static let addBag = "Add bag"
        static let snapTip = "Tip: include chargers and liquids so we can check the rules."
        static let tripTitle = "Trip details"
        static let tripCaption = "We check TSA, airline and destination rules"
        static let from = "From"
        static let to = "To"
        static let dates = "Dates"
        static let airlineBag = "Airline & bag"
        static let addFlight = "Add your flight"
        static let noForecast = "Add your flight to see the weather there."
        static func weatherIn(_ place: String?) -> String { place.map { "Weather in \($0)" } ?? "Weather at destination" }
        static let forecastTag = "Forecast"
        static let lastYearTag = "Last year"
        static let loadingWeather = "Checking the weather…"
        static let weatherNeedsDates = "Add your travel dates to see the weather."
        static let weatherFailed = "Couldn’t load the weather. Pack layers to be safe."
        static let retry = "Try again"
        static func tempRange(low: Int, high: Int, fahrenheit: Bool) -> String {
            "\(low)° – \(high)°\(fahrenheit ? "F" : "C")"
        }
        static let fahrenheit = "Fahrenheit"
        static let celsius = "Celsius"
        static func wetDays(_ wet: Int, of total: Int) -> String {
            wet == 0 ? "Dry all \(total) days" : "Rain or snow on \(wet) of \(total) days"
        }
        static let lastYearNote = "Too far ahead for a forecast, so this is the same dates last year."
        static func clampedNote(_ last: Date) -> String {
            "The forecast only reaches \(last.formatted(DestinationWeather.dayStyle.month(.abbreviated).day())). Check again closer to the trip."
        }
        static let packingIdeas = "Packing ideas"
        static let optimize = "Optimize my packing"
        static func optimizeCaption(_ items: Int) -> String {
            "Takes a few seconds · \(items) item\(items == 1 ? "" : "s"), 1 bag"
        }
        static let needTrip = "Add your flight and at least one item first."
        static let alerts = "Rule flags"
    }

    enum Results {
        static let title = "Your results"
        static let wholeBag = "Whole bag"
        static let repack = "Pack again"
        static let rotateHint = "Drag to rotate"
        static func full(_ pct: Double) -> String { String(format: "%.0f%% full", pct) }
        static let views = ["3D", "Top", "Side"]
        static let layers = "Layers"
        static let layerNames = ["All", "Bottom", "Middle", "Top"]
        static let spaceUsed = "bag space used"
        static func ofLimit(_ kg: Double) -> String { String(format: "of %.0f kg limit", kg) }
        static let itemsFit = "items fit"
        static func flagged(_ n: Int) -> String { n == 1 ? "Heads up: 1 item flagged" : "Heads up: \(n) items flagged" }
        static let flaggedCaption = "Sort these out before you fly"
        static let allRules = "See all rules"
        static let filterAll = "All"
        static let filterTSA = "TSA"
        static let filterAirline = "Airline"
        static let filterDestination = "Destination"
        static func leftOut(_ n: Int) -> String { n == 1 ? "1 item didn’t fit" : "\(n) items didn’t fit" }
        static let leftOutCaption = "Wear the bulky ones on the plane, or tap one for why"
        static let shortTooLarge = "too big"
        static let shortFragile = "fragile in the way"
        static let shortNoRoom = "no room"
        static let shortInvalid = "size missing"
        static let seePlan = "See my packing plan"
        static let empty = "No plan yet. Add your trip, bag and items on Home, then tap Optimize."
        static let goHome = "Go to Home"
        static let routeItem = "Everyone on this route"
    }

    enum PackingPlan {
        static let title = "Packing plan"
        static func progress(_ pct: Int) -> String { pct >= 100 ? "All packed!" : "You’re \(pct)% packed!" }
        static func stepsDone(_ done: Int, _ total: Int, minutes: Int) -> String {
            let left = minutes == 0 ? "ready to zip" : "about \(minutes) min to go"
            return "\(done) of \(total) steps done · \(left)"
        }
        static func layerChip(_ name: String, _ done: Int, _ total: Int) -> String {
            done == total ? "\(name) · done" : "\(name) · \(done)/\(total)"
        }
        static func step(_ n: Int) -> String { "Step \(n)" }
        static let bottomTitle = "Bottom layer"
        static let bottomCaption = "Heavy and flat items sit by the wheels"
        static let middleTitle = "Middle layer"
        static let middleCaption = "Soft, bulky things fill the gaps"
        static let topTitle = "Top layer"
        static let topCaption = "Grab-first items and security stuff"
        static func nextTo(_ names: [String]) -> String { "Next to " + names.prefix(2).joined(separator: " and ") }
        static let proTip = "Pro tip"
        static let proTipBody = "Rolled soft clothes slip into the gaps between bulky items, so nothing shifts in transit."
        static let allPacked = "I’m all packed!"
        static let shareTitle = "My Snugly packing plan"
        static let empty = "No plan yet. Pack your bag from Home first."
    }

    enum Flags {
        static let tsaBadge = "TSA rule"
        static let airlineBadge = "Airline rule"
        static let destinationBadge = "Destination law"
        static let mustFix = "Must fix"
        static let leaveHome = "Leave at home"
        static let needsApproval = "Needs approval"
        static let checkFirst = "Check first"
        static let stale = "· stale"
        static func source(_ days: Int) -> String { "Source · verified \(days) days ago" }
    }

    enum Errors {
        static let generic = "Something went wrong."
        static let retry = "Try again"
        static let network = "Couldn’t reach the server. Using offline demo data."
        static let serverUnreachable = "Couldn’t reach the server. Check your connection and try again."
    }

    enum Loading {
        static let identifyingTitle = "Identifying your items"
        static let scanWait = "Usually 3–8 seconds."
        static let inventoryWait = "Usually 5–15 seconds."
        static func identified(_ done: Int, of total: Int) -> String { "\(done) of \(total) done" }
        static let packingTitle = "Optimizing your packing"
        static let packingWait = "Checking the rules and fitting everything into your bag."
    }
}
