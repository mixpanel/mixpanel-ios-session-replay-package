//
//  EventTriggerTests.swift
//  MixpanelSessionReplayTests
//
//  Created by Mixpanel on 2026-03-03.
//

import XCTest

@testable import MixpanelSessionReplay

class EventTriggerTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - RecordingEventTrigger Codable Tests

    func testEventTriggerDecoding() throws {
        let json = """
            {
                "percentage": 50.0,
                "property_filters": {
                    "==": [{"var": "plan_type"}, "premium"]
                }
            }
            """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let trigger = try decoder.decode(RecordingEventTrigger.self, from: data)

        XCTAssertEqual(trigger.percentage, 50.0)
        XCTAssertNotNil(trigger.propertyFilters)
        XCTAssertTrue(trigger.propertyFilters!.keys.contains("=="))
    }

    func testEventTriggerDecodingWithoutFilters() throws {
        let json = """
            {
                "percentage": 100.0
            }
            """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let trigger = try decoder.decode(RecordingEventTrigger.self, from: data)

        XCTAssertEqual(trigger.percentage, 100.0)
        XCTAssertNil(trigger.propertyFilters)
    }

    func testRecordingSettingsDecoding() throws {
        let json = """
            {
                "recording": {
                "is_enabled": true
                },
                "sdk_config": {
                "config": {
                    "record_sessions_percent": 10,
                    "recording_event_triggers": {
                        "load": {
                            "percentage": 75,
                            "property_filters": {
                                ">": [
                                    {
                                        "var": "$lib_version"
                                    },
                                    "5.2.0"
                                ]
                            }
                        }
                    }
                }
                }
            }
            """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let settings = try decoder.decode(SettingsResponse.self, from: data)

        XCTAssertNotNil(settings.recording)
        XCTAssertTrue(settings.recording?.isEnabled ?? false)
        XCTAssertNotNil(settings.sdkConfig?.config?.recordingEventTriggers)
        XCTAssertEqual(settings.sdkConfig?.config?.recordingEventTriggers?.count, 1)
        XCTAssertNotNil(settings.sdkConfig?.config?.recordingEventTriggers?["load"])
        XCTAssertEqual(settings.sdkConfig?.config?.recordingEventTriggers?["load"]?.percentage, 75)
    }

    // MARK: - RecordingEventTriggerEvaluator Tests

    func testEventNameMatching() {
        let triggers: [String: RecordingEventTrigger] = [
            "purchase_completed": RecordingEventTrigger(percentage: 100, propertyFilters: nil)
        ]

        let evaluator = RecordingEventTriggerEvaluator(triggers: triggers)

        let result = evaluator.shouldStartRecording(
            for: "purchase_completed",
            properties: [:]
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result, 100.0)
    }

    func testEventNameNotMatching() {
        let triggers: [String: RecordingEventTrigger] = [
            "purchase_completed": RecordingEventTrigger(percentage: 100, propertyFilters: nil)
        ]

        let evaluator = RecordingEventTriggerEvaluator(triggers: triggers)

        let result = evaluator.shouldStartRecording(
            for: "other_event",
            properties: [:]
        )

        XCTAssertNil(result)
    }

    func testSamplingPercentageZero() {
        let triggers: [String: RecordingEventTrigger] = [
            "test_event": RecordingEventTrigger(percentage: 0, propertyFilters: nil)
        ]

        let evaluator = RecordingEventTriggerEvaluator(triggers: triggers)

        let result = evaluator.shouldStartRecording(
            for: "test_event",
            properties: [:]
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result, 0.0)
    }

    func testSamplingPercentage100() {
        let triggers: [String: RecordingEventTrigger] = [
            "test_event": RecordingEventTrigger(percentage: 100, propertyFilters: nil)
        ]

        let evaluator = RecordingEventTriggerEvaluator(triggers: triggers)

        let result = evaluator.shouldStartRecording(
            for: "test_event",
            properties: [:]
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result, 100.0)
    }

    func testSamplingPercentage50() {
        let triggers: [String: RecordingEventTrigger] = [
            "test_event": RecordingEventTrigger(percentage: 50, propertyFilters: nil)
        ]

        let evaluator = RecordingEventTriggerEvaluator(triggers: triggers)

        // The evaluator returns the percentage, it doesn't perform sampling
        let result = evaluator.shouldStartRecording(for: "test_event", properties: [:])

        XCTAssertNotNil(result)
        XCTAssertEqual(result, 50.0)
    }

    func testPropertyFilterMatching() {
        // Use JSON decoding to ensure filter structure matches production
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    "===": [{"var": "plan_type"}, "premium"]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)

        let triggers: [String: RecordingEventTrigger] = [
            "test_event": trigger
        ]

        let evaluator = RecordingEventTriggerEvaluator(triggers: triggers)

        let result = evaluator.shouldStartRecording(
            for: "test_event",
            properties: ["plan_type": "premium"]
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result, 100.0)
    }

    func testPropertyFilterNotMatching() {
        // Use JSON decoding to ensure filter structure matches production
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    "===": [{"var": "plan_type"}, "premium"]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)

        let triggers: [String: RecordingEventTrigger] = [
            "test_event": trigger
        ]

        let evaluator = RecordingEventTriggerEvaluator(triggers: triggers)

        let result = evaluator.shouldStartRecording(
            for: "test_event",
            properties: ["plan_type": "basic"]
        )

        XCTAssertNil(result)
    }

    func testPropertyFilterWithMissingProperty() {
        // Use JSON decoding to ensure filter structure matches production
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    "===": [{"var": "plan_type"}, "premium"]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)

        let triggers: [String: RecordingEventTrigger] = [
            "test_event": trigger
        ]

        let evaluator = RecordingEventTriggerEvaluator(triggers: triggers)

        let result = evaluator.shouldStartRecording(
            for: "test_event",
            properties: [:]  // Empty properties
        )

        XCTAssertNil(result)
    }

    func testMultipleTriggers() {
        let triggers: [String: RecordingEventTrigger] = [
            "event1": RecordingEventTrigger(percentage: 100, propertyFilters: nil),
            "event2": RecordingEventTrigger(percentage: 50, propertyFilters: nil),
            "event3": RecordingEventTrigger(percentage: 25, propertyFilters: nil),
        ]

        let evaluator = RecordingEventTriggerEvaluator(triggers: triggers)

        let result1 = evaluator.shouldStartRecording(for: "event1", properties: [:])
        XCTAssertEqual(result1, 100.0)

        let result2 = evaluator.shouldStartRecording(for: "event2", properties: [:])
        XCTAssertEqual(result2, 50.0)

        let result3 = evaluator.shouldStartRecording(for: "event3", properties: [:])
        XCTAssertEqual(result3, 25.0)
    }

    // MARK: - Comparison Operator Tests (Real-World Cases)

    func testNumericGreaterThan() {
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    ">": [{"var": "score"}, 80]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)
        let evaluator = RecordingEventTriggerEvaluator(triggers: ["high_score": trigger])

        // Score above threshold
        let result1 = evaluator.shouldStartRecording(for: "high_score", properties: ["score": 85])
        XCTAssertNotNil(result1)
        XCTAssertEqual(result1, 100.0)

        // Score equal to threshold (should not match)
        let result2 = evaluator.shouldStartRecording(for: "high_score", properties: ["score": 80])
        XCTAssertNil(result2)

        // Score below threshold
        let result3 = evaluator.shouldStartRecording(for: "high_score", properties: ["score": 75])
        XCTAssertNil(result3)
    }

    func testNumericLessThanOrEqual() {
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    "<=": [{"var": "age"}, 18]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)
        let evaluator = RecordingEventTriggerEvaluator(triggers: ["underage_user": trigger])

        // Age below threshold
        let result1 = evaluator.shouldStartRecording(for: "underage_user", properties: ["age": 17])
        XCTAssertNotNil(result1)
        XCTAssertEqual(result1, 100.0)

        // Age equal to threshold (should match)
        let result2 = evaluator.shouldStartRecording(for: "underage_user", properties: ["age": 18])
        XCTAssertNotNil(result2)
        XCTAssertEqual(result2, 100.0)

        // Age above threshold
        let result3 = evaluator.shouldStartRecording(for: "underage_user", properties: ["age": 25])
        XCTAssertNil(result3)
    }

    func testNumericRangeCheck() {
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    "and": [
                        {">=": [{"var": "price"}, 10]},
                        {"<=": [{"var": "price"}, 100]}
                    ]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)
        let evaluator = RecordingEventTriggerEvaluator(triggers: ["product_view": trigger])

        // Price in range
        let result1 = evaluator.shouldStartRecording(for: "product_view", properties: ["price": 50])
        XCTAssertNotNil(result1)
        XCTAssertEqual(result1, 100.0)

        // Price at lower boundary
        let result2 = evaluator.shouldStartRecording(for: "product_view", properties: ["price": 10])
        XCTAssertNotNil(result2)

        // Price at upper boundary
        let result3 = evaluator.shouldStartRecording(for: "product_view", properties: ["price": 100])
        XCTAssertNotNil(result3)

        // Price below range
        let result4 = evaluator.shouldStartRecording(for: "product_view", properties: ["price": 5])
        XCTAssertNil(result4)

        // Price above range
        let result5 = evaluator.shouldStartRecording(for: "product_view", properties: ["price": 150])
        XCTAssertNil(result5)
    }

    // MARK: - IN Operator Tests (Array Membership & Substring)

    func testArrayMembershipCityTargeting() {
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    "in": [{"var": "$city"}, ["Louisville", "Miami", "SF"]]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)
        let evaluator = RecordingEventTriggerEvaluator(triggers: ["geo_event": trigger])

        // City in list
        let result1 = evaluator.shouldStartRecording(for: "geo_event", properties: ["$city": "Louisville"])
        XCTAssertNotNil(result1)
        XCTAssertEqual(result1, 100.0)

        let result2 = evaluator.shouldStartRecording(for: "geo_event", properties: ["$city": "SF"])
        XCTAssertNotNil(result2)

        // City not in list
        let result3 = evaluator.shouldStartRecording(for: "geo_event", properties: ["$city": "Boston"])
        XCTAssertNil(result3)
    }

    func testSubstringEmailDomain() {
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    "in": ["gmail", {"var": "$email"}]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)
        let evaluator = RecordingEventTriggerEvaluator(triggers: ["signup": trigger])

        // Email contains substring
        let result1 = evaluator.shouldStartRecording(for: "signup", properties: ["$email": "user@gmail.com"])
        XCTAssertNotNil(result1)
        XCTAssertEqual(result1, 100.0)

        // Email doesn't contain substring
        let result2 = evaluator.shouldStartRecording(for: "signup", properties: ["$email": "user@yahoo.com"])
        XCTAssertNil(result2)

        // Partial match in domain
        let result3 = evaluator.shouldStartRecording(for: "signup", properties: ["$email": "admin@mygmail.org"])
        XCTAssertNotNil(result3)
    }

    // MARK: - Complex AND/OR Logic Tests

    func testCityAndAgeTargeting() {
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    "and": [
                        {"in": [{"var": "$city"}, ["Louisville", "Miami"]]},
                        {">=": [{"var": "$age"}, 21]}
                    ]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)
        let evaluator = RecordingEventTriggerEvaluator(triggers: ["purchase": trigger])

        // Both conditions met
        let result1 = evaluator.shouldStartRecording(for: "purchase", properties: ["$city": "Louisville", "$age": 25])
        XCTAssertNotNil(result1)
        XCTAssertEqual(result1, 100.0)

        // Right city, wrong age
        let result2 = evaluator.shouldStartRecording(for: "purchase", properties: ["$city": "Miami", "$age": 18])
        XCTAssertNil(result2)

        // Wrong city, right age
        let result3 = evaluator.shouldStartRecording(for: "purchase", properties: ["$city": "Boston", "$age": 25])
        XCTAssertNil(result3)

        // Neither condition met
        let result4 = evaluator.shouldStartRecording(for: "purchase", properties: ["$city": "Boston", "$age": 18])
        XCTAssertNil(result4)
    }

    func testAccountTierOrCredits() {
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    "and": [
                        {"or": [
                            {"===": [{"var": "$tier"}, "premium"]},
                            {"===": [{"var": "$tier"}, "enterprise"]}
                        ]},
                        {">": [{"var": "$credits"}, 0]}
                    ]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)
        let evaluator = RecordingEventTriggerEvaluator(triggers: ["feature_access": trigger])

        // Premium tier with credits
        let result1 = evaluator.shouldStartRecording(
            for: "feature_access", properties: ["$tier": "premium", "$credits": 100])
        XCTAssertNotNil(result1)
        XCTAssertEqual(result1, 100.0)

        // Enterprise tier with credits
        let result2 = evaluator.shouldStartRecording(
            for: "feature_access", properties: ["$tier": "enterprise", "$credits": 50])
        XCTAssertNotNil(result2)

        // Premium tier but no credits
        let result3 = evaluator.shouldStartRecording(
            for: "feature_access", properties: ["$tier": "premium", "$credits": 0])
        XCTAssertNil(result3)

        // Free tier with credits
        let result4 = evaluator.shouldStartRecording(
            for: "feature_access", properties: ["$tier": "free", "$credits": 100])
        XCTAssertNil(result4)
    }

    func testEmailDomainAndScore() {
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    "and": [
                        {"in": ["gmail", {"var": "$email"}]},
                        {">": [{"var": "$score"}, 80]}
                    ]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)
        let evaluator = RecordingEventTriggerEvaluator(triggers: ["conversion": trigger])

        // Gmail domain and high score
        let result1 = evaluator.shouldStartRecording(
            for: "conversion", properties: ["$email": "user@gmail.com", "$score": 85])
        XCTAssertNotNil(result1)
        XCTAssertEqual(result1, 100.0)

        // Gmail domain but low score
        let result2 = evaluator.shouldStartRecording(
            for: "conversion", properties: ["$email": "user@gmail.com", "$score": 70])
        XCTAssertNil(result2)

        // Non-Gmail domain with high score
        let result3 = evaluator.shouldStartRecording(
            for: "conversion", properties: ["$email": "user@yahoo.com", "$score": 90])
        XCTAssertNil(result3)
    }

    // MARK: - Strict Inequality Tests

    func testStrictInequality() {
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    "!==": [{"var": "$status"}, "banned"]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)
        let evaluator = RecordingEventTriggerEvaluator(triggers: ["user_action": trigger])

        // Status is not banned
        let result1 = evaluator.shouldStartRecording(for: "user_action", properties: ["$status": "active"])
        XCTAssertNotNil(result1)
        XCTAssertEqual(result1, 100.0)

        // Status is banned
        let result2 = evaluator.shouldStartRecording(for: "user_action", properties: ["$status": "banned"])
        XCTAssertNil(result2)
    }

    func testTrialEligibility() {
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    "and": [
                        {"!==": [{"var": "$status"}, "banned"]},
                        {"<": [{"var": "$trial_days"}, 30]}
                    ]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)
        let evaluator = RecordingEventTriggerEvaluator(triggers: ["trial_feature": trigger])

        // Active status within trial period
        let result1 = evaluator.shouldStartRecording(
            for: "trial_feature", properties: ["$status": "active", "$trial_days": 15])
        XCTAssertNotNil(result1)
        XCTAssertEqual(result1, 100.0)

        // Banned status
        let result2 = evaluator.shouldStartRecording(
            for: "trial_feature", properties: ["$status": "banned", "$trial_days": 15])
        XCTAssertNil(result2)

        // Trial expired
        let result3 = evaluator.shouldStartRecording(
            for: "trial_feature", properties: ["$status": "active", "$trial_days": 30])
        XCTAssertNil(result3)
    }

    // MARK: - Multiple Event Triggers

    func testMultipleEventsWithDifferentFilters() {
        let purchaseJson = """
            {
                "percentage": 100,
                "property_filters": {
                    ">": [{"var": "amount"}, 100]
                }
            }
            """
        let signupJson = """
            {
                "percentage": 50,
                "property_filters": {
                    "in": ["gmail", {"var": "email"}]
                }
            }
            """
        let viewJson = """
            {
                "percentage": 25,
                "property_filters": {
                    "===": [{"var": "premium"}, true]
                }
            }
            """

        let purchaseTrigger = try! JSONDecoder().decode(
            RecordingEventTrigger.self, from: purchaseJson.data(using: .utf8)!)
        let signupTrigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: signupJson.data(using: .utf8)!)
        let viewTrigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: viewJson.data(using: .utf8)!)

        let triggers: [String: RecordingEventTrigger] = [
            "purchase": purchaseTrigger,
            "signup": signupTrigger,
            "view": viewTrigger,
        ]

        let evaluator = RecordingEventTriggerEvaluator(triggers: triggers)

        // Test purchase event
        let purchase1 = evaluator.shouldStartRecording(for: "purchase", properties: ["amount": 150])
        XCTAssertEqual(purchase1, 100.0)

        let purchase2 = evaluator.shouldStartRecording(for: "purchase", properties: ["amount": 50])
        XCTAssertNil(purchase2)

        // Test signup event
        let signup1 = evaluator.shouldStartRecording(for: "signup", properties: ["email": "user@gmail.com"])
        XCTAssertEqual(signup1, 50.0)

        let signup2 = evaluator.shouldStartRecording(for: "signup", properties: ["email": "user@yahoo.com"])
        XCTAssertNil(signup2)

        // Test view event
        let view1 = evaluator.shouldStartRecording(for: "view", properties: ["premium": true])
        XCTAssertEqual(view1, 25.0)

        let view2 = evaluator.shouldStartRecording(for: "view", properties: ["premium": false])
        XCTAssertNil(view2)
    }

    // MARK: - Edge Cases

    func testMissingPropertyReturnsNil() {
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    "===": [{"var": "plan_type"}, "premium"]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)
        let evaluator = RecordingEventTriggerEvaluator(triggers: ["test_event": trigger])

        // Missing property should return nil (var returns null, === throws error)
        let result = evaluator.shouldStartRecording(for: "test_event", properties: [:])
        XCTAssertNil(result)
    }

    func testFloatingPointComparison() {
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    ">=": [{"var": "rating"}, 4.5]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)
        let evaluator = RecordingEventTriggerEvaluator(triggers: ["review": trigger])

        // Rating above threshold
        let result1 = evaluator.shouldStartRecording(for: "review", properties: ["rating": 4.8])
        XCTAssertNotNil(result1)
        XCTAssertEqual(result1, 100.0)

        // Rating exactly at threshold
        let result2 = evaluator.shouldStartRecording(for: "review", properties: ["rating": 4.5])
        XCTAssertNotNil(result2)

        // Rating below threshold
        let result3 = evaluator.shouldStartRecording(for: "review", properties: ["rating": 4.2])
        XCTAssertNil(result3)
    }

    func testBooleanStrictEquality() {
        let json = """
            {
                "percentage": 100,
                "property_filters": {
                    "===": [{"var": "is_student"}, true]
                }
            }
            """
        let trigger = try! JSONDecoder().decode(RecordingEventTrigger.self, from: json.data(using: .utf8)!)
        let evaluator = RecordingEventTriggerEvaluator(triggers: ["discount": trigger])

        // Boolean true
        let result1 = evaluator.shouldStartRecording(for: "discount", properties: ["is_student": true])
        XCTAssertNotNil(result1)
        XCTAssertEqual(result1, 100.0)

        // Boolean false
        let result2 = evaluator.shouldStartRecording(for: "discount", properties: ["is_student": false])
        XCTAssertNil(result2)
    }
}
