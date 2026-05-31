import Foundation

struct CostResult: Hashable {
    let period: Period
    let energyCost: Decimal          // pricePerUnit * consumption
    let baseFee: Decimal             // proportional Grundgebühr
    let feedInRevenue: Decimal       // bei PV-Einspeisung
    var total: Decimal { energyCost + baseFee - feedInRevenue }
    var netForDisplay: Decimal { energyCost + baseFee + feedInRevenue == 0 ? 0 : total }
}

struct CostCalculator {
    let meter: Meter
    let tariffs: [Tariff]
    let consumption: ConsumptionCalculator

    init(meter: Meter) {
        self.meter = meter
        self.tariffs = meter.tariffs.sorted { $0.validFrom < $1.validFrom }
        self.consumption = ConsumptionCalculator(meter: meter)
    }

    /// Calculates costs in a period by integrating tariff segments inside the period
    /// (so a tariff change mid-period is correctly accounted for).
    func cost(in period: Period, calendar: Calendar = .current) -> CostResult {
        guard !tariffs.isEmpty else {
            return CostResult(period: period, energyCost: 0, baseFee: 0, feedInRevenue: 0)
        }

        var energy: Decimal = 0
        var base: Decimal = 0
        var feedIn: Decimal = 0
        let isFeedInMeter = meter.type == .electricityFeedIn

        // Build segments: for each tariff, compute its overlapping subperiod and multiply.
        for tariff in tariffs {
            let segStart = max(period.start, tariff.validFrom)
            let segEnd = min(period.end, tariff.validTo ?? .distantFuture)
            if segEnd <= segStart { continue }

            let segPeriod = Period(granularity: .day, start: segStart, end: segEnd)
            let segConsumption = consumption.consumption(in: segPeriod, calendar: calendar).amount
            if isFeedInMeter, let feedInPrice = tariff.feedInPricePerUnit {
                feedIn += segConsumption * feedInPrice
            } else {
                energy += segConsumption * tariff.pricePerUnit
            }

            // Base fee: tariff.baseFeePerMonth proportional to seconds in segment
            let seconds = segEnd.timeIntervalSince(segStart)
            let secondsPerMonth: Double = 86_400 * 30.4375 // average month length
            let monthFraction = Decimal(seconds / secondsPerMonth)
            base += tariff.baseFeePerMonth * monthFraction
        }

        return CostResult(period: period, energyCost: energy, baseFee: base, feedInRevenue: feedIn)
    }

    /// Returns the tariff valid on `date`, if any.
    func activeTariff(on date: Date) -> Tariff? {
        tariffs.first { $0.isActive(on: date) }
    }
}
