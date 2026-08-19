//
//  ExchangeRateTestKey.swift
//  Zashi
//
//  Created by Lukáš Korba on 08-02-2024.
//

@preconcurrency import Combine

extension ExchangeRateClient {
    static let noOp = Self(
        exchangeRateEventStream: { Empty().eraseToAnyPublisher() },
        rateAvailability: { .loading },
        refreshExchangeRateUSD: { },
        selectedCurrency: { .usd }
    )
}
