import Foundation
import HealthKit
import Capacitor

// Read-only bridge to Apple Health for the Kalori web app:
//   requestAuth()            asks once for read access (active energy, resting energy, body mass)
//   dayEnergy({date})        kcal burned on that day: { active, basal }  (date "YYYY-MM-DD", default today)
//   latestWeight()           newest body-mass sample: { kg, date }  (or {} when there is none)
//   dayWorkouts({date})      workouts that started that day: { list: [{ id, type (HKWorkoutActivityType raw), min, kcal, start "HH:mm", source }] }
// Nothing is written to Health and nothing leaves the phone.
@objc(KaloriHealthPlugin)
public class KaloriHealthPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "KaloriHealthPlugin"
    public let jsName = "KaloriHealth"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestAuth", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "dayEnergy", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "latestWeight", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "dayWorkouts", returnType: CAPPluginReturnPromise)
    ]
    private let store = HKHealthStore()
    private var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>()
        if let t = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .bodyMass) { s.insert(t) }
        s.insert(HKObjectType.workoutType())
        return s
    }

    @objc func isAvailable(_ call: CAPPluginCall) {
        call.resolve(["available": HKHealthStore.isHealthDataAvailable()])
    }

    @objc func requestAuth(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else { call.resolve(["ok": false]); return }
        store.requestAuthorization(toShare: nil, read: readTypes) { ok, err in
            if let err = err { call.reject(err.localizedDescription); return }
            call.resolve(["ok": ok])   // iOS never says whether reading was allowed; empty answers mean "not allowed" or "no data"
        }
    }

    private func dayRange(_ s: String?) -> (Date, Date) {
        let cal = Calendar.current
        var start = cal.startOfDay(for: Date())
        if let s = s {
            let f = DateFormatter(); f.calendar = cal; f.timeZone = TimeZone.current; f.dateFormat = "yyyy-MM-dd"
            if let d = f.date(from: s) { start = cal.startOfDay(for: d) }
        }
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return (start, min(end, Date()))
    }

    private func sum(_ id: HKQuantityTypeIdentifier, _ start: Date, _ end: Date, _ done: @escaping (Double) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { done(0); return }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
            done(stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
        }
        store.execute(q)
    }

    @objc func dayEnergy(_ call: CAPPluginCall) {
        let (start, end) = dayRange(call.getString("date"))
        if end <= start { call.resolve(["active": 0, "basal": 0]); return }
        sum(.activeEnergyBurned, start, end) { active in
            self.sum(.basalEnergyBurned, start, end) { basal in
                call.resolve(["active": active, "basal": basal])
            }
        }
    }

    @objc func latestWeight(_ call: CAPPluginCall) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { call.resolve([:]); return }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            guard let s = samples?.first as? HKQuantitySample else { call.resolve([:]); return }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone.current
            call.resolve(["kg": s.quantity.doubleValue(for: .gramUnit(with: .kilo)), "date": f.string(from: s.startDate)])
        }
        store.execute(q)
    }

    @objc func dayWorkouts(_ call: CAPPluginCall) {
        let (start, end) = dayRange(call.getString("date"))
        if end <= start { call.resolve(["list": []]); return }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: pred, limit: 50, sortDescriptors: [sort]) { _, samples, _ in
            let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = TimeZone.current
            var list: [[String: Any]] = []
            for case let w as HKWorkout in samples ?? [] {
                var kcal: Double = 0
                if #available(iOS 16.0, *), let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
                   let q = w.statistics(for: t)?.sumQuantity() {
                    kcal = q.doubleValue(for: .kilocalorie())
                } else if let e = w.totalEnergyBurned {
                    kcal = e.doubleValue(for: .kilocalorie())
                }
                list.append(["id": w.uuid.uuidString, "type": Int(w.workoutActivityType.rawValue),
                             "min": Int((w.duration / 60).rounded()), "kcal": Int(kcal.rounded()),
                             "start": f.string(from: w.startDate), "source": w.sourceRevision.source.name])
            }
            call.resolve(["list": list])
        }
        store.execute(q)
    }
}
