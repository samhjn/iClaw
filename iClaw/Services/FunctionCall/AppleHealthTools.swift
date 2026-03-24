import Foundation
import HealthKit

struct AppleHealthTools {
    private var store: HKHealthStore { ApplePermissionManager.shared.healthStore }

    // MARK: - Read

    func readSteps(arguments: [String: Any]) async -> String {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return "[Error] Step count type is unavailable on this device."
        }
        if let err = await ApplePermissionManager.shared.ensureHealthAccess(read: [quantityType], write: []) { return err }

        let (start, end) = resolveDateRange(arguments: arguments, defaultDays: 7)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    continuation.resume(returning: "[Error] Failed to read steps: \(error.localizedDescription)")
                    return
                }
                let count = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: """
                Steps summary:
                - Range: \(formatDate(start)) to \(formatDate(end))
                - Total steps: \(Int(count))
                """)
            }
            store.execute(query)
        }
    }

    func readHeartRate(arguments: [String: Any]) async -> String {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return "[Error] Heart rate type is unavailable on this device."
        }
        if let err = await ApplePermissionManager.shared.ensureHealthAccess(read: [type], write: []) { return err }

        let (start, end) = resolveDateRange(arguments: arguments, defaultDays: 1)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        do {
            let samples = try await fetchQuantitySamples(type: type, predicate: predicate, limit: 200)
            if samples.isEmpty {
                return "(No heart-rate samples found between \(formatDate(start)) and \(formatDate(end)))"
            }

            let unit = HKUnit.count().unitDivided(by: .minute())
            let values = samples.map { $0.quantity.doubleValue(for: unit) }
            let avg = values.reduce(0, +) / Double(values.count)
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 0

            return """
            Heart rate summary:
            - Range: \(formatDate(start)) to \(formatDate(end))
            - Samples: \(values.count)
            - Avg: \(String(format: "%.1f", avg)) bpm
            - Min: \(String(format: "%.0f", minV)) bpm
            - Max: \(String(format: "%.0f", maxV)) bpm
            """
        } catch {
            return "[Error] Failed to read heart rate: \(error.localizedDescription)"
        }
    }

    func readSleep(arguments: [String: Any]) async -> String {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return "[Error] Sleep analysis type is unavailable on this device."
        }
        if let err = await ApplePermissionManager.shared.ensureHealthAccess(read: [type], write: []) { return err }

        let (start, end) = resolveDateRange(arguments: arguments, defaultDays: 7)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        do {
            let samples = try await fetchCategorySamples(type: type, predicate: predicate, limit: 500)
            if samples.isEmpty {
                return "(No sleep samples found between \(formatDate(start)) and \(formatDate(end)))"
            }

            var totalSleepSeconds: TimeInterval = 0
            var totalInBedSeconds: TimeInterval = 0

            for sample in samples {
                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                if isAsleepSample(sample.value) {
                    totalSleepSeconds += duration
                } else if sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                    totalInBedSeconds += duration
                }
            }

            return """
            Sleep summary:
            - Range: \(formatDate(start)) to \(formatDate(end))
            - Samples: \(samples.count)
            - Asleep: \(formatDuration(totalSleepSeconds))
            - In bed: \(formatDuration(totalInBedSeconds))
            """
        } catch {
            return "[Error] Failed to read sleep data: \(error.localizedDescription)"
        }
    }

    func readBodyMass(arguments: [String: Any]) async -> String {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return "[Error] Body mass type is unavailable on this device."
        }
        if let err = await ApplePermissionManager.shared.ensureHealthAccess(read: [type], write: []) { return err }

        let (start, end) = resolveDateRange(arguments: arguments, defaultDays: 30)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        do {
            let samples = try await fetchQuantitySamples(type: type, predicate: predicate, limit: 50)
            if samples.isEmpty {
                return "(No body-mass samples found between \(formatDate(start)) and \(formatDate(end)))"
            }

            let unitLabel = (arguments["unit"] as? String)?.lowercased() ?? "kg"
            let unit: HKUnit = (unitLabel == "lb" || unitLabel == "lbs") ? .pound() : .gramUnit(with: .kilo)

            let rows = samples.prefix(20).map { sample in
                let v = sample.quantity.doubleValue(for: unit)
                return "- \(formatDate(sample.endDate)): \(String(format: "%.2f", v)) \(unitLabel == "lb" || unitLabel == "lbs" ? "lb" : "kg")"
            }.joined(separator: "\n")

            return """
            Body mass samples:
            - Range: \(formatDate(start)) to \(formatDate(end))
            - Count: \(samples.count)
            \(rows)
            """
        } catch {
            return "[Error] Failed to read body mass: \(error.localizedDescription)"
        }
    }

    // MARK: - Write

    func writeDietaryEnergy(arguments: [String: Any]) async -> String {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else {
            return "[Error] Dietary energy type is unavailable on this device."
        }
        if let err = await ApplePermissionManager.shared.ensureHealthAccess(read: [], write: [type]) { return err }

        guard let kcal = (arguments["kcal"] as? Double) ?? (arguments["energy_kcal"] as? Double) else {
            return "[Error] Missing required parameter: kcal"
        }
        if kcal <= 0 {
            return "[Error] kcal must be a positive number."
        }

        let when = parseDate(arguments["date"] as? String) ?? Date()
        let end = when
        let start = Calendar.current.date(byAdding: .minute, value: -1, to: end) ?? end
        let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)

        var metadata: [String: Any] = [:]
        if let meal = arguments["meal"] as? String, !meal.isEmpty {
            metadata[HKMetadataKeyFoodType] = meal
        }
        if let note = arguments["note"] as? String, !note.isEmpty {
            metadata["iClawNote"] = note
        }

        let sample = HKQuantitySample(type: type, quantity: quantity, start: start, end: end, metadata: metadata.isEmpty ? nil : metadata)

        do {
            try await saveSample(sample)
            return """
            Dietary energy written successfully.
            - Energy: \(String(format: "%.1f", kcal)) kcal
            - Date: \(formatDate(end))
            - Source: iClaw
            """
        } catch {
            return "[Error] Failed to write dietary energy: \(error.localizedDescription)"
        }
    }

    func writeBodyMass(arguments: [String: Any]) async -> String {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return "[Error] Body mass type is unavailable on this device."
        }
        if let err = await ApplePermissionManager.shared.ensureHealthAccess(read: [], write: [type]) { return err }

        guard let value = arguments["value"] as? Double else {
            return "[Error] Missing required parameter: value"
        }
        if value <= 0 {
            return "[Error] value must be a positive number."
        }

        let unitLabel = (arguments["unit"] as? String)?.lowercased() ?? "kg"
        let unit: HKUnit = (unitLabel == "lb" || unitLabel == "lbs") ? .pound() : .gramUnit(with: .kilo)

        let when = parseDate(arguments["date"] as? String) ?? Date()
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: when, end: when)

        do {
            try await saveSample(sample)
            return """
            Body mass written successfully.
            - Value: \(String(format: "%.2f", value)) \(unitLabel == "lb" || unitLabel == "lbs" ? "lb" : "kg")
            - Date: \(formatDate(when))
            - Source: iClaw
            """
        } catch {
            return "[Error] Failed to write body mass: \(error.localizedDescription)"
        }
    }

    func writeDietaryWater(arguments: [String: Any]) async -> String {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            return "[Error] Dietary water type is unavailable on this device."
        }
        if let err = await ApplePermissionManager.shared.ensureHealthAccess(read: [], write: [type]) { return err }

        guard let ml = (arguments["ml"] as? Double) ?? (arguments["value"] as? Double) else {
            return "[Error] Missing required parameter: ml"
        }
        if ml <= 0 {
            return "[Error] ml must be a positive number."
        }

        let when = parseDate(arguments["date"] as? String) ?? Date()
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: when, end: when)

        do {
            try await saveSample(sample)
            return """
            Dietary water written successfully.
            - Water: \(String(format: "%.0f", ml)) ml
            - Date: \(formatDate(when))
            - Source: iClaw
            """
        } catch {
            return "[Error] Failed to write dietary water: \(error.localizedDescription)"
        }
    }

    func writeDietaryCarbohydrates(arguments: [String: Any]) async -> String {
        await writeNutrient(arguments: arguments, id: .dietaryCarbohydrates, gramsKey: "grams", defaultLabel: "carbohydrates")
    }

    func writeDietaryProtein(arguments: [String: Any]) async -> String {
        await writeNutrient(arguments: arguments, id: .dietaryProtein, gramsKey: "grams", defaultLabel: "protein")
    }

    func writeDietaryFat(arguments: [String: Any]) async -> String {
        await writeNutrient(arguments: arguments, id: .dietaryFatTotal, gramsKey: "grams", defaultLabel: "fat")
    }

    func writeWorkout(arguments: [String: Any]) async -> String {
        let workoutType = HKObjectType.workoutType()
        if let err = await ApplePermissionManager.shared.ensureHealthAccess(read: [], write: [workoutType]) { return err }

        guard let start = parseDate(arguments["start_date"] as? String) else {
            return "[Error] Missing or invalid start_date. Use ISO 8601 or yyyy-MM-dd HH:mm."
        }
        let end = parseDate(arguments["end_date"] as? String) ?? Date()
        if end <= start {
            return "[Error] end_date must be later than start_date."
        }

        let activity = parseWorkoutActivity(arguments["activity_type"] as? String)
        let kcal = arguments["energy_kcal"] as? Double
        let distanceKm = arguments["distance_km"] as? Double

        do {
            let config = HKWorkoutConfiguration()
            config.activityType = activity
            config.locationType = .unknown

            let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: nil)
            try await beginCollection(builder: builder, at: start)

            var samples: [HKSample] = []
            if let kcal,
               let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
                samples.append(HKQuantitySample(type: energyType, quantity: quantity, start: start, end: end))
            }
            if let distanceKm,
               let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
                let quantity = HKQuantity(unit: .meter(), doubleValue: distanceKm * 1000.0)
                samples.append(HKQuantitySample(type: distanceType, quantity: quantity, start: start, end: end))
            }
            if !samples.isEmpty {
                try await addSamples(samples, to: builder)
            }

            try await endCollection(builder: builder, at: end)
            _ = try await finishWorkout(builder: builder)

            var lines = [
                "Workout written successfully.",
                "- Activity: \(activity.name)",
                "- Start: \(formatDate(start))",
                "- End: \(formatDate(end))"
            ]
            if let kcal { lines.append("- Energy: \(String(format: "%.1f", kcal)) kcal") }
            if let distanceKm { lines.append("- Distance: \(String(format: "%.2f", distanceKm)) km") }
            lines.append("- Source: iClaw")
            return lines.joined(separator: "\n")
        } catch {
            return "[Error] Failed to write workout: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func fetchQuantitySamples(type: HKQuantityType, predicate: NSPredicate?, limit: Int) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }

    private func fetchCategorySamples(type: HKCategoryType, predicate: NSPredicate?, limit: Int) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
    }

    private func saveSample(_ sample: HKSample) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(sample) { ok, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if ok {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "AppleHealthTools",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Unknown save failure"]
                    ))
                }
            }
        }
    }

    private func beginCollection(builder: HKWorkoutBuilder, at start: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: start) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "AppleHealthTools",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to begin workout collection"]
                    ))
                }
            }
        }
    }

    private func addSamples(_ samples: [HKSample], to builder: HKWorkoutBuilder) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.add(samples) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "AppleHealthTools",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to add workout samples"]
                    ))
                }
            }
        }
    }

    private func endCollection(builder: HKWorkoutBuilder, at end: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: end) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "AppleHealthTools",
                        code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to end workout collection"]
                    ))
                }
            }
        }
    }

    private func finishWorkout(builder: HKWorkoutBuilder) async throws -> HKWorkout {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKWorkout, Error>) in
            builder.finishWorkout { workout, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let workout {
                    continuation.resume(returning: workout)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "AppleHealthTools",
                        code: -5,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to finish workout"]
                    ))
                }
            }
        }
    }

    private func writeNutrient(
        arguments: [String: Any],
        id: HKQuantityTypeIdentifier,
        gramsKey: String,
        defaultLabel: String
    ) async -> String {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else {
            return "[Error] \(defaultLabel.capitalized) type is unavailable on this device."
        }
        if let err = await ApplePermissionManager.shared.ensureHealthAccess(read: [], write: [type]) { return err }

        guard let grams = (arguments[gramsKey] as? Double) ?? (arguments["value"] as? Double) else {
            return "[Error] Missing required parameter: \(gramsKey)"
        }
        if grams <= 0 {
            return "[Error] \(gramsKey) must be a positive number."
        }

        let when = parseDate(arguments["date"] as? String) ?? Date()
        let quantity = HKQuantity(unit: .gram(), doubleValue: grams)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: when, end: when)

        do {
            try await saveSample(sample)
            return """
            Dietary \(defaultLabel) written successfully.
            - \(defaultLabel.capitalized): \(String(format: "%.1f", grams)) g
            - Date: \(formatDate(when))
            - Source: iClaw
            """
        } catch {
            return "[Error] Failed to write dietary \(defaultLabel): \(error.localizedDescription)"
        }
    }

    private func resolveDateRange(arguments: [String: Any], defaultDays: Int) -> (Date, Date) {
        let end = parseDate(arguments["end_date"] as? String) ?? Date()
        if let start = parseDate(arguments["start_date"] as? String) {
            return (start, end)
        }
        let start = Calendar.current.date(byAdding: .day, value: -defaultDays, to: end) ?? end
        return (start, end)
    }

    private func parseDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let formats = ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            f.dateFormat = format
            if let d = f.date(from: text) { return d }
        }
        return ISO8601DateFormatter().date(from: text)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return "\(h)h \(m)m"
    }

    private func isAsleepSample(_ value: Int) -> Bool {
        if value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue { return true }
        if #available(iOS 16.0, *) {
            return value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
        }
        return false
    }

    private func parseWorkoutActivity(_ raw: String?) -> HKWorkoutActivityType {
        guard let raw else { return .other }
        switch raw.lowercased() {
        case "running", "run": return .running
        case "walking", "walk": return .walking
        case "cycling", "bike": return .cycling
        case "swimming", "swim": return .swimming
        case "hiking", "hike": return .hiking
        case "yoga": return .yoga
        case "functional_strength_training", "strength", "weights": return .functionalStrengthTraining
        case "traditional_strength_training": return .traditionalStrengthTraining
        case "high_intensity_interval_training", "hiit": return .highIntensityIntervalTraining
        case "elliptical": return .elliptical
        case "rowing": return .rowing
        case "stair_climbing", "stairs": return .stairClimbing
        case "mixed_cardio", "cardio": return .mixedCardio
        default: return .other
        }
    }
}

private extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .hiking: return "hiking"
        case .yoga: return "yoga"
        case .functionalStrengthTraining: return "functional_strength_training"
        case .traditionalStrengthTraining: return "traditional_strength_training"
        case .highIntensityIntervalTraining: return "high_intensity_interval_training"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        case .stairClimbing: return "stair_climbing"
        case .mixedCardio: return "mixed_cardio"
        default: return "other"
        }
    }
}
