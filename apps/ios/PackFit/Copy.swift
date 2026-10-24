import Foundation

enum Copy {
    enum App {
        static let name = "PackFit"
        static let tagline = "Scan it. Pack it. Fly home under 23 kg."
    }

    enum Onboarding {
        static let skip = "Skip"
        static let next = "Next"
        static let done = "Get started"
        static let s1Title = "Measure with your phone"
        static let s1Body = "LiDAR on Pro models sizes each item. Other phones use a credit card for scale."
        static let s2Title = "See the packing plan in 3D"
        static let s2Body = "Step through exactly where each item goes in your bag."
        static let s3Title = "Rules with sources"
        static let s3Body = "Flags link to TSA, airline, or customs pages. Guidance only — not the final word."
    }

    enum Trip {
        static let title = "Your trip"
        static let sampleHeader = "Sample trips"
        static let newTrip = "New trip"
        static let continueButton = "Choose bag"
        static let empty = "Pick a sample trip to start the demo."
    }

    enum Bag {
        static let title = "Your bag"
        static let presets = "Presets"
        static let custom = "Custom"
        static let measureLidar = "Measure with LiDAR"
        static let measureCamera = "Measure with the camera"
        static let measureManual = "Enter dimensions"
        static let wheelsPrompt = "Where are the wheels?"
        static let wheelsBack = "Back"
        static let wheelsBottom = "Bottom"
        static let continueItems = "Add items"
        static let weightLimit = "Weight limit (kg)"
    }

    enum Items {
        static let title = "Items"
        static let scan = "Scan item"
        static let pack = "Pack bag"
        static let empty = "No items yet. Scan three things from the pile."
        static let emptyAction = "Scan an item"
        static let delete = "Delete"
    }

    enum Scan {
        static let title = "Scan"
        static let lidarMeasuring = "LiDAR measuring"
        static let referenceCardHint = "Place a credit card next to the item"
        static let simulatorMode = "Simulator — enter dimensions"
        static let findPlane = "Point at a table or floor until a plane appears."
        static let tapCorners = "Tap two opposite corners of the item’s base."
        static let tapTop = "Optional: tap the top to set height."
        static let confirmBox = "Does this box look right?"
        static let retap = "Measure again"
        static let capture = "Identify item"
        static let waiting = "Identifying… usually 3–8 seconds."
        static let save = "Add to list"
        static let manualFallback = "We kept your measurements. Fill in the rest."
        static let looksRight = "Looks right"
        static let checkSize = "Check the size"
        static let pleaseMeasure = "Please measure"
        static let measuredLidar = "Measured with LiDAR"
        static let measuredManual = "Entered manually"
        static let measuredReference = "Scaled from credit card"
        static let measuredARTaps = "Measured with AR taps"
    }

    enum Guided {
        static let title = "Scan & pack"
        static let findFloor = "Point at the floor and move the phone slowly."
        static let bag = "Open your suitcase on the floor, then tap the bottom of the empty shell."
        static let bagMeasuring = "Measuring the bag… hold the phone above it."
        static let bagStable = "Got it. Tap “Use this bag”."
        static let tapNoDepth = "Couldn’t see that spot. Move a little closer and tap again."
        static let itemNotFound = "Couldn’t find an item there. Tap the middle of it from a little closer."

        static func bagFailure(_ failure: CavityFitter.Failure) -> String {
            switch failure {
            case .seedUnseen: return "Hold the phone above the bag so it can see inside."
            case .leaked: return "That spot isn’t inside the bag. Tap the bottom of the open shell."
            case .tooSmall: return "That space is too small for a suitcase. Tap the bottom of the main shell."
            case .noWalls: return "Couldn’t find the bag’s walls. Move the phone slowly around the bag."
            }
        }
        static let useBag = "Use this bag"
        static let tapCorners = "Measure by tapping corners"
        static let tapCornerLeft = "Open the bag on the floor. Tap the inside back-left corner."
        static let tapCornerRight = "Now tap the inside back-right corner."
        static let tapCornerFront = "Now tap an inside front corner."
        static let cornersTooClose = "Those corners are too close. Try again."
        static let tapMissed = "Couldn’t find the floor there. Move the phone a little and tap again."
        static let heightMissed = "Couldn’t read the height. Tap the top edge of the side facing you."
        static let measureByTapping = "Measure by corners instead"
        static let backToSweep = "Back to one-tap"
        static let tapItemCorner1 = "Tap a bottom corner of an item."
        static let tapItemCorner2 = "Tap the next bottom corner along one side."
        static let tapItemCorner3 = "Tap a bottom corner on the opposite side."
        static let tapItemTop = "Tap the top edge of the side facing you."
        static let tapItemAdjust = "Check the size, then add the item."
        static let addItem = "Add item"
        static let redo = "Redo"
        static let lengthCm = "Length"
        static let widthCm = "Width"
        static let heightCm = "Height"
        static let items = "Tap an item to measure it. Keep it in view until its box turns green."
        static let itemsMeasuring = "Measuring… keep the item in view."
        static let itemsHint = "Tap an item again to re-measure it."
        static let removeItem = "Remove item"
        static let itemsFound = "items found"
        static let done = "Done"
        static let identifying = "Identifying your items…"
        static let review = "Check your items"
        static let packIt = "Pack it"
        static let rescan = "Scan again"
        static let packing = "Working out the plan…"
        static let overlay = "Follow the steps. Each box shows where an item goes."
        static let underLid = "Above the rim: this goes under the lid."
        static let unknownItem = "Item"
        static let usePresets = "Use bag presets instead"
        static let addManually = "Add one manually"
        static let view3D = "3D view"
        static let itemsLink = "Items"
        static let restart = "Start over"
        static let noAR = "This device can’t run AR. Choose a bag preset instead."
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
    }

    enum Rules {
        static let title = "Travel rules"
        static let stale = "Some sources are older than 30 days. Double-check before you fly."
        static let empty = "No flags for these items on this trip."
        static let guidance = "Guidance only — not authority."
        static let verifiedPrefix = "Verified"
        static let daysAgo = "days ago"
    }

    enum Errors {
        static let generic = "Something went wrong."
        static let retry = "Try again"
        static let network = "Couldn’t reach the server. Using offline demo data."
    }
}
