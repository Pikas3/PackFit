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
