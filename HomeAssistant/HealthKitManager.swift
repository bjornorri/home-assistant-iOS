//
//  HeathKitManager.swift
//  HomeAssistant
//
//  Created by Bjorn Orri Saemundsson on 08/02/2018.
//  Copyright © 2018 Robbie Trencheny. All rights reserved.
//

import HealthKit
import PromiseKit

class HealthKitManager {

    private enum HealthKitError: Error {
        case notAvailableOnDevice
        case dataTypeNotAvailable
    }

    private static let healthStore = HKHealthStore()

    private static var characteristicTypes: Set<HKCharacteristicType> {
        var ids: [HKCharacteristicTypeIdentifier] = [
            .biologicalSex,
            .bloodType,
            .dateOfBirth,
            .fitzpatrickSkinType
        ]
        if #available(iOS 10.0, *) {
            ids.append(.wheelchairUse)
        }
        let types = ids.flatMap({ HKObjectType.characteristicType(forIdentifier: $0) })
        return Set(types)
    }

    private static var quantityTypes: Set<HKSampleType> {
        var ids: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned,
            .basalBodyTemperature,
            .basalEnergyBurned,
            .bloodAlcoholContent,
            .bloodGlucose,
            .bloodPressureDiastolic,
            .bloodPressureSystolic,
            .bodyFatPercentage,
            .bodyMass,
            .bodyMassIndex,
            .bodyTemperature,
            .dietaryBiotin,
            .dietaryCaffeine,
            .dietaryCalcium,
            .dietaryCarbohydrates,
            .dietaryChloride,
            .dietaryCholesterol,
            .dietaryChromium,
            .dietaryCopper,
            .dietaryEnergyConsumed,
            .dietaryFatMonounsaturated,
            .dietaryFatPolyunsaturated,
            .dietaryFatSaturated,
            .dietaryFatTotal,
            .dietaryFiber,
            .dietaryFolate,
            .dietaryIodine,
            .dietaryIron,
            .dietaryMagnesium,
            .dietaryManganese,
            .dietaryMolybdenum,
            .dietaryNiacin,
            .dietaryPantothenicAcid,
            .dietaryPhosphorus,
            .dietaryPotassium,
            .dietaryProtein,
            .dietaryRiboflavin,
            .dietarySelenium,
            .dietarySodium,
            .dietarySugar,
            .dietaryThiamin,
            .dietaryVitaminA,
            .dietaryVitaminB12,
            .dietaryVitaminB6,
            .dietaryVitaminC,
            .dietaryVitaminD,
            .dietaryVitaminE,
            .dietaryVitaminK,
            .dietaryWater,
            .dietaryZinc,
            .distanceCycling,
            .electrodermalActivity,
            .flightsClimbed,
            .forcedExpiratoryVolume1,
            .forcedVitalCapacity,
            .heartRate,
            .height,
            .inhalerUsage,
            .leanBodyMass,
            .nikeFuel,
            .numberOfTimesFallen,
            .oxygenSaturation,
            .peakExpiratoryFlowRate,
            .peripheralPerfusionIndex,
            .respiratoryRate,
            .stepCount,
            .uvExposure
        ]
        if #available(iOS 9.3, *) {
            ids.append(.appleExerciseTime)
        }
        if #available(iOS 10.0, *) {
            ids.append(.distanceSwimming)
            ids.append(.distanceWheelchair)
            ids.append(.pushCount)
            ids.append(.swimmingStrokeCount)
        }
        if #available(iOS 11.0, *) {
            ids.append(.heartRateVariabilitySDNN)
            ids.append(.insulinDelivery)
            ids.append(.restingHeartRate)
            ids.append(.vo2Max)
            ids.append(.waistCircumference)
            ids.append(.walkingHeartRateAverage)
        }
        if #available(iOS 11.2, *) {
            ids.append(.distanceDownhillSnowSports)
        }
        let types = ids.flatMap({ HKObjectType.quantityType(forIdentifier: $0) })
        return Set(types)
    }

    private static var categoryTypes: Set<HKCategoryType> {
        var ids: [HKCategoryTypeIdentifier] = [
            .appleStandHour,
            .cervicalMucusQuality,
            .intermenstrualBleeding,
            .menstrualFlow,
            .ovulationTestResult,
            .sexualActivity,
            .sleepAnalysis
        ]
        if #available(iOS 10.0, *) {
            ids.append(.mindfulSession)
        }
        let types = ids.flatMap({ HKObjectType.categoryType(forIdentifier: $0) })
        return Set(types)
    }

    private static var sampleTypes: Set<HKSampleType> {
        let categories = categoryTypes as Set<HKSampleType>
        let quantities = quantityTypes as Set<HKSampleType>
        return categories.union(quantities)
    }

    private static var allTypes: Set<HKObjectType> {
        let characteristics = characteristicTypes as Set<HKObjectType>
        let categories = categoryTypes as Set<HKObjectType>
        let quantities = quantityTypes as Set<HKObjectType>
        return characteristics.union(categories).union(quantities)
    }

    class func authorizeHealthKit(completion: @escaping (Bool, Error?) -> Void) {
        // Check if HealthKit is available
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, HealthKitError.notAvailableOnDevice)
            return
        }

        healthStore.requestAuthorization(toShare: nil, read: allTypes) { (success, error) in
            completion(success, error)
        }
    }

    class func setup() {
        enableBackgroundDelivery()
    }

    private class func enableBackgroundDelivery() {
        sampleTypes.forEach({ type in
            healthStore.enableBackgroundDelivery(for: type, frequency: .immediate, withCompletion: {success, _ in
                if success {
                    observeUpdates(forType: type)
                }
            })
        })
    }

    private class func observeUpdates(forType type: HKSampleType) {
        let query = HKObserverQuery(sampleType: type, predicate: nil, updateHandler: {_, completion, _ in
            firstly {
                getMostRecentSample(forType: type)
            }.then {
                processSample($0)
            }.always {
                completion()
            }
        })
        healthStore.execute(query)
    }

    private class func getMostRecentSample(forType type: HKSampleType) -> Promise<HKSample> {
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        return Promise {fulfill, reject in
            let query = HKSampleQuery(sampleType: type,
                                      predicate: nil,
                                      limit: 1,
                                      sortDescriptors: sort,
                                      resultsHandler: {_, samples, _ in
                if let sample = samples?.first {
                    fulfill(sample)
                } else {
                    reject(HealthKitError.dataTypeNotAvailable)
                }
            })
            healthStore.execute(query)
        }
    }

    private class func processSample(_ sample: HKSample) {
        // For now we only process quantity samples
        if let sample = sample as? HKQuantitySample {
            print("\(sample.quantityType): \(sample.quantity) (\(sample.startDate) - \(sample.endDate))")
        }
    }
}
