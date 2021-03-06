//
//  Web3+Structures.swift
//
//  Created by Alexander Vlasov on 26.12.2017.
//  Copyright © 2017 Bankex Foundation. All rights reserved.
//

import BigInt
import Foundation

fileprivate func decodeHexToData<T>(_ container: KeyedDecodingContainer<T>, key: KeyedDecodingContainer<T>.Key, allowOptional: Bool = false) throws -> Data? {
    if allowOptional {
        let string = try? container.decode(String.self, forKey: key)
        if string != nil {
            guard let data = Data.fromHex(string!) else { throw Web3Error.dataError }
            return data
        }
        return nil
    } else {
        let string = try container.decode(String.self, forKey: key)
        guard let data = Data.fromHex(string) else { throw Web3Error.dataError }
        return data
    }
}

fileprivate func decodeHexToBigUInt<T>(_ container: KeyedDecodingContainer<T>, key: KeyedDecodingContainer<T>.Key, allowOptional: Bool = false) throws -> BigUInt? {
    if allowOptional {
        let string = try? container.decode(String.self, forKey: key)
        if string != nil {
            guard let number = BigUInt(string!.withoutHex, radix: 16) else { throw Web3Error.dataError }
            return number
        }
        return nil
    } else {
        let string = try container.decode(String.self, forKey: key)
        guard let number = BigUInt(string.withoutHex, radix: 16) else { throw Web3Error.dataError }
        return number
    }
}

extension Web3Options: Decodable {
    enum CodingKeys: String, CodingKey {
        case from
        case to
        case gasPrice
        case gas
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let gasLimit = try decodeHexToBigUInt(container, key: .gas)
        self.gasLimit = gasLimit

        let gasPrice = try decodeHexToBigUInt(container, key: .gasPrice)
        self.gasPrice = gasPrice

        let toString = try container.decode(String?.self, forKey: .to)
        var to: Address?
        if toString == nil || toString == "0x" || toString == "0x0" {
            to = Address.contractDeployment
        } else {
            guard let addressString = toString else { throw Web3Error.dataError }
            let ethAddr = Address(addressString)
            guard ethAddr.isValid else { throw Web3Error.dataError }
            to = ethAddr
        }
        self.to = to
        let from = try container.decodeIfPresent(Address.self, forKey: .to)
//        var from: Address?
//        if fromString != nil {
//            guard let ethAddr = Address(toString) else { throw Web3Error.dataError }
//            from = ethAddr
//        }
        self.from = from

        let value = try decodeHexToBigUInt(container, key: .value)
        self.value = value
    }
}

extension EthereumTransaction: Decodable {
    enum CodingKeys: String, CodingKey {
        case to
        case data
        case input
        case nonce
        case v
        case r
        case s
        case value
    }

    public init(from decoder: Decoder) throws {
        let options = try Web3Options(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)

        var data = try decodeHexToData(container, key: .data, allowOptional: true)
        if data != nil {
            self.data = data!
        } else {
            data = try decodeHexToData(container, key: .input, allowOptional: true)
            if data != nil {
                self.data = data!
            } else {
                throw Web3Error.dataError
            }
        }

        guard let nonce = try decodeHexToBigUInt(container, key: .nonce) else { throw Web3Error.dataError }
        self.nonce = nonce

        guard let v = try decodeHexToBigUInt(container, key: .v) else { throw Web3Error.dataError }
        self.v = v

        guard let r = try decodeHexToBigUInt(container, key: .r) else { throw Web3Error.dataError }
        self.r = r

        guard let s = try decodeHexToBigUInt(container, key: .s) else { throw Web3Error.dataError }
        self.s = s

        if options.value == nil || options.to == nil || options.gasLimit == nil || options.gasPrice == nil {
            throw Web3Error.dataError
        }
        chainID = nil
        value = options.value!
        to = options.to!
        gasPrice = options.gasPrice!
        gasLimit = options.gasLimit!

        if let inferedChainID = inferedChainID, v >= 37 {
            chainID = inferedChainID
        }
    }
}

public struct TransactionDetails: Decodable {
    public var blockHash: Data?
    public var blockNumber: BigUInt?
    public var transactionIndex: BigUInt?
    public var transaction: EthereumTransaction

    enum CodingKeys: String, CodingKey {
        case blockHash
        case blockNumber
        case transactionIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let blockNumber = try decodeHexToBigUInt(container, key: .blockNumber, allowOptional: true)
        self.blockNumber = blockNumber

        let blockHash = try decodeHexToData(container, key: .blockHash, allowOptional: true)
        self.blockHash = blockHash

        let transactionIndex = try decodeHexToBigUInt(container, key: .blockNumber, allowOptional: true)
        self.transactionIndex = transactionIndex

        let transaction = try EthereumTransaction(from: decoder)
        self.transaction = transaction
    }

    public init(_ json: [String: Any]) throws {
        if let value = try? json.at("blockHash") {
            blockHash = try value.data()
        }
        transaction = try EthereumTransaction(json)
        if let value = try? json.at("blockNumber") {
            blockNumber = try value.uint256()
        }
        if let value = try? json.at("transactionIndex") {
            transactionIndex = try value.uint256()
        }
    }
}

public struct TransactionReceipt: Decodable {
    public var transactionHash: Data
    public var blockHash: Data
    public var blockNumber: BigUInt
    public var transactionIndex: BigUInt
    public var contractAddress: Address?
    public var cumulativeGasUsed: BigUInt
    public var gasUsed: BigUInt
    public var logs: [EventLog]
    public var status: TXStatus
    public var logsBloom: EthereumBloomFilter?

    public enum TXStatus {
        case ok
        case failed
        case notYetProcessed
    }

    enum CodingKeys: String, CodingKey {
        case blockHash
        case blockNumber
        case transactionHash
        case transactionIndex
        case contractAddress
        case cumulativeGasUsed
        case gasUsed
        case logs
        case logsBloom
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let blockNumber = try decodeHexToBigUInt(container, key: .blockNumber) else { throw Web3Error.dataError }
        self.blockNumber = blockNumber

        guard let blockHash = try decodeHexToData(container, key: .blockHash) else { throw Web3Error.dataError }
        self.blockHash = blockHash

        guard let transactionIndex = try decodeHexToBigUInt(container, key: .transactionIndex) else { throw Web3Error.dataError }
        self.transactionIndex = transactionIndex

        guard let transactionHash = try decodeHexToData(container, key: .transactionHash) else { throw Web3Error.dataError }
        self.transactionHash = transactionHash

        let contractAddress = try container.decodeIfPresent(Address.self, forKey: .contractAddress)
        if contractAddress != nil {
            self.contractAddress = contractAddress
        }

        guard let cumulativeGasUsed = try decodeHexToBigUInt(container, key: .cumulativeGasUsed) else { throw Web3Error.dataError }
        self.cumulativeGasUsed = cumulativeGasUsed

        guard let gasUsed = try decodeHexToBigUInt(container, key: .gasUsed) else { throw Web3Error.dataError }
        self.gasUsed = gasUsed

        let status = try decodeHexToBigUInt(container, key: .status, allowOptional: true)
        if status == nil {
            self.status = TXStatus.notYetProcessed
        } else if status == 1 {
            self.status = TXStatus.ok
        } else {
            self.status = TXStatus.failed
        }

        let logsData = try decodeHexToData(container, key: .logsBloom, allowOptional: true)
        if logsData != nil && logsData!.count > 0 {
            logsBloom = EthereumBloomFilter(logsData!)
        }

        let logs = try container.decode([EventLog].self, forKey: .logs)
        self.logs = logs
    }

    public init(transactionHash: Data, blockHash: Data, blockNumber: BigUInt, transactionIndex: BigUInt, contractAddress: Address?, cumulativeGasUsed: BigUInt, gasUsed: BigUInt, logs: [EventLog], status: TXStatus, logsBloom: EthereumBloomFilter?) {
        self.transactionHash = transactionHash
        self.blockHash = blockHash
        self.blockNumber = blockNumber
        self.transactionIndex = transactionIndex
        self.contractAddress = contractAddress
        self.cumulativeGasUsed = cumulativeGasUsed
        self.gasUsed = gasUsed
        self.logs = logs
        self.status = status
        self.logsBloom = logsBloom
    }

    static func notProcessed(transactionHash: Data) -> TransactionReceipt {
        let receipt = TransactionReceipt(transactionHash: transactionHash, blockHash: Data(), blockNumber: BigUInt(0), transactionIndex: BigUInt(0), contractAddress: nil, cumulativeGasUsed: BigUInt(0), gasUsed: BigUInt(0), logs: [EventLog](), status: .notYetProcessed, logsBloom: nil)
        return receipt
    }
}

extension Address: Decodable, Encodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stringValue = try container.decode(String.self)
        self.init(stringValue)
    }

    public func encode(to encoder: Encoder) throws {
        let value = address.lowercased()
        var signleValuedCont = encoder.singleValueContainer()
        try signleValuedCont.encode(value)
    }
}

public struct EventLog: Decodable {
    public var address: Address
    public var blockHash: Data
    public var blockNumber: BigUInt
    public var data: Data
    public var logIndex: BigUInt
    public var removed: Bool
    public var topics: [Data]
    public var transactionHash: Data
    public var transactionIndex: BigUInt

//    address = 0x53066cddbc0099eb6c96785d9b3df2aaeede5da3;
//    blockHash = 0x779c1f08f2b5252873f08fd6ec62d75bb54f956633bbb59d33bd7c49f1a3d389;
//    blockNumber = 0x4f58f8;
//    data = 0x0000000000000000000000000000000000000000000000004563918244f40000;
//    logIndex = 0x84;
//    removed = 0;
//    topics =     (
//    0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
//    0x000000000000000000000000efdcf2c36f3756ce7247628afdb632fa4ee12ec5,
//    0x000000000000000000000000d5395c132c791a7f46fa8fc27f0ab6bacd824484
//    );
//    transactionHash = 0x9f7bb2633abb3192d35f65e50a96f9f7ca878fa2ee7bf5d3fca489c0c60dc79a;
//    transactionIndex = 0x99;

    enum CodingKeys: String, CodingKey {
        case address
        case blockHash
        case blockNumber
        case data
        case logIndex
        case removed
        case topics
        case transactionHash
        case transactionIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let address = try container.decode(Address.self, forKey: .address)
        self.address = address

        guard let blockNumber = try decodeHexToBigUInt(container, key: .blockNumber) else { throw Web3Error.dataError }
        self.blockNumber = blockNumber

        guard let blockHash = try decodeHexToData(container, key: .blockHash) else { throw Web3Error.dataError }
        self.blockHash = blockHash

        guard let transactionIndex = try decodeHexToBigUInt(container, key: .transactionIndex) else { throw Web3Error.dataError }
        self.transactionIndex = transactionIndex

        guard let transactionHash = try decodeHexToData(container, key: .transactionHash) else { throw Web3Error.dataError }
        self.transactionHash = transactionHash

        guard let data = try decodeHexToData(container, key: .data) else { throw Web3Error.dataError }
        self.data = data

        guard let logIndex = try decodeHexToBigUInt(container, key: .logIndex) else { throw Web3Error.dataError }
        self.logIndex = logIndex

        let removed = try decodeHexToBigUInt(container, key: .removed, allowOptional: true)
        if removed == 1 {
            self.removed = true
        } else {
            self.removed = false
        }

        let topicsStrings = try container.decode([String].self, forKey: .topics)
        var allTopics = [Data]()
        for top in topicsStrings {
            guard let topic = Data.fromHex(top) else { throw Web3Error.dataError }
            allTopics.append(topic)
        }
        topics = allTopics
    }
}

public enum TransactionInBlockError: Error {
    case corrupted
}

public enum TransactionInBlock: Decodable {
    case hash(Data)
    case transaction(EthereumTransaction)
    case null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let string = try? value.decode(String.self) {
            guard let d = Data.fromHex(string) else { throw Web3Error.dataError }
            self = .hash(d)
        } else if let dict = try? value.decode([String: String].self) {
//            guard let t = try? EthereumTransaction(from: decoder) else { throw Web3Error.dataError }
            let t = try EthereumTransaction(dict)
            self = .transaction(t)
        } else {
            self = .null
        }
    }

    public init(_ data: Any) throws {
        if let string = data as? String {
            guard let d = Data.fromHex(string) else { throw TransactionInBlockError.corrupted }
            self = .hash(d)
        } else if let dict = data as? [String: Any] {
            let t = try EthereumTransaction(dict)
            self = .transaction(t)
        } else {
            throw TransactionInBlockError.corrupted
        }
    }
}

public struct Block: Decodable {
    public var number: BigUInt
    public var hash: Data
    public var parentHash: Data
    public var nonce: Data?
    public var sha3Uncles: Data
    public var logsBloom: EthereumBloomFilter?
    public var transactionsRoot: Data
    public var stateRoot: Data
    public var receiptsRoot: Data
    public var miner: Address?
    public var difficulty: BigUInt
    public var totalDifficulty: BigUInt
    public var extraData: Data
    public var size: BigUInt
    public var gasLimit: BigUInt
    public var gasUsed: BigUInt
    public var timestamp: Date
    public var transactions: [TransactionInBlock]
    public var uncles: [Data]

    enum CodingKeys: String, CodingKey {
        case number
        case hash
        case parentHash
        case nonce
        case sha3Uncles
        case logsBloom
        case transactionsRoot
        case stateRoot
        case receiptsRoot
        case miner
        case difficulty
        case totalDifficulty
        case extraData
        case size
        case gasLimit
        case gasUsed
        case timestamp
        case transactions
        case uncles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let number = try decodeHexToBigUInt(container, key: .number) else { throw Web3Error.dataError }
        self.number = number

        guard let hash = try decodeHexToData(container, key: .hash) else { throw Web3Error.dataError }
        self.hash = hash

        guard let parentHash = try decodeHexToData(container, key: .parentHash) else { throw Web3Error.dataError }
        self.parentHash = parentHash

        let nonce = try decodeHexToData(container, key: .nonce, allowOptional: true)
        self.nonce = nonce

        guard let sha3Uncles = try decodeHexToData(container, key: .sha3Uncles) else { throw Web3Error.dataError }
        self.sha3Uncles = sha3Uncles

        let logsBloomData = try decodeHexToData(container, key: .logsBloom, allowOptional: true)
        var bloom: EthereumBloomFilter?
        if logsBloomData != nil {
            bloom = EthereumBloomFilter(logsBloomData!)
        }
        logsBloom = bloom

        guard let transactionsRoot = try decodeHexToData(container, key: .transactionsRoot) else { throw Web3Error.dataError }
        self.transactionsRoot = transactionsRoot

        guard let stateRoot = try decodeHexToData(container, key: .stateRoot) else { throw Web3Error.dataError }
        self.stateRoot = stateRoot

        guard let receiptsRoot = try decodeHexToData(container, key: .receiptsRoot) else { throw Web3Error.dataError }
        self.receiptsRoot = receiptsRoot

        if let minerAddress = try? container.decode(String.self, forKey: .miner) {
            guard minerAddress.isAddress else { throw Web3Error.dataError }
            miner = Address(minerAddress)
        }

        guard let difficulty = try decodeHexToBigUInt(container, key: .difficulty) else { throw Web3Error.dataError }
        self.difficulty = difficulty

        guard let totalDifficulty = try decodeHexToBigUInt(container, key: .totalDifficulty) else { throw Web3Error.dataError }
        self.totalDifficulty = totalDifficulty

        guard let extraData = try decodeHexToData(container, key: .extraData) else { throw Web3Error.dataError }
        self.extraData = extraData

        guard let size = try decodeHexToBigUInt(container, key: .size) else { throw Web3Error.dataError }
        self.size = size

        guard let gasLimit = try decodeHexToBigUInt(container, key: .gasLimit) else { throw Web3Error.dataError }
        self.gasLimit = gasLimit

        guard let gasUsed = try decodeHexToBigUInt(container, key: .gasUsed) else { throw Web3Error.dataError }
        self.gasUsed = gasUsed

        let timestampString = try container.decode(String.self, forKey: .timestamp).withoutHex
        guard let timestampInt = UInt64(timestampString, radix: 16) else { throw Web3Error.dataError }
        let timestamp = Date(timeIntervalSince1970: TimeInterval(timestampInt))
        self.timestamp = timestamp

        let transactions = try container.decode([TransactionInBlock].self, forKey: .transactions)
        self.transactions = transactions

        let unclesStrings = try container.decode([String].self, forKey: .uncles)
        var uncles = [Data]()
        for str in unclesStrings {
            guard let d = Data.fromHex(str) else { throw Web3Error.dataError }
            uncles.append(d)
        }
        self.uncles = uncles
    }
}

public struct EventParserResult: EventParserResultProtocol {
    public var eventName: String
    public var transactionReceipt: TransactionReceipt?
    public var contractAddress: Address
    public var decodedResult: [String: Any]
    public var eventLog: EventLog?

    public init(eventName: String, transactionReceipt: TransactionReceipt?, contractAddress: Address, decodedResult: [String: Any]) {
        self.eventName = eventName
        self.transactionReceipt = transactionReceipt
        self.contractAddress = contractAddress
        self.decodedResult = decodedResult
        eventLog = nil
    }
}

public struct TransactionSendingResult {
    public var transaction: EthereumTransaction
    public var hash: String
}
