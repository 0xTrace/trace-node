class EthTransaction < T::Struct
  include SysConfig
  
  # ESIP event signatures for detecting Ethscription events
  def self.event_signature(event_name)
    '0x' + Eth::Util.keccak256(event_name).unpack1('H*')
  end
  
  CreateEthscriptionEventSig = event_signature("ethscriptions_protocol_CreateEthscription(address,string)")
  Esip1EventSig = event_signature("ethscriptions_protocol_TransferEthscription(address,bytes32)")
  Esip2EventSig = event_signature("ethscriptions_protocol_TransferEthscriptionForPreviousOwner(address,address,bytes32)")
  
  const :block_hash, Hash32
  const :block_number, Integer
  const :block_timestamp, Integer
  const :tx_hash, Hash32
  const :transaction_index, Integer
  const :input, ByteString
  const :chain_id, T.nilable(Integer)
  const :from_address, Address20
  const :to_address, T.nilable(Address20)
  const :status, Integer
  const :logs, T::Array[T.untyped], default: []
  const :eth_block, T.nilable(EthBlock)
  const :ethscription_transactions, T::Array[EthscriptionTransaction], default: []

  # Alias for consistency with ethscription_detector
  sig { returns(Hash32) }
  def transaction_hash
    tx_hash
  end

  sig { params(block_result: T.untyped, receipt_result: T.untyped).returns(T::Array[EthTransaction]) }
  def self.from_rpc_result(block_result, receipt_result)
    block_hash = block_result['hash']
    block_number = block_result['number'].to_i(16)
    
    indexed_receipts = receipt_result.index_by{|el| el['transactionHash']}
    
    block_result['transactions'].map do |tx|
      current_receipt = indexed_receipts[tx['hash']]
      
      EthTransaction.new(
        block_hash: Hash32.from_hex(block_hash),
        block_number: block_number,
        block_timestamp: block_result['timestamp'].to_i(16),
        tx_hash: Hash32.from_hex(tx['hash']),
        transaction_index: tx['transactionIndex'].to_i(16),
        input: ByteString.from_hex(tx['input']),
        chain_id: tx['chainId']&.to_i(16),
        from_address: Address20.from_hex(tx['from']),
        to_address: tx['to'] ? Address20.from_hex(tx['to']) : nil,
        status: current_receipt['status'].to_i(16),
        logs: current_receipt['logs'],
      )
    end
  end
  
  sig { params(block_results: T.untyped, receipt_results: T.untyped, ethscriptions_block: EthscriptionsBlock).returns(T::Array[EthscriptionTransaction]) }
  def self.ethscription_txs_from_rpc_results(block_results, receipt_results, ethscriptions_block)
    eth_txs = from_rpc_result(block_results, receipt_results)

    # Collect all deposits from all transactions
    all_deposits = []
    eth_txs.sort_by(&:transaction_index).each do |eth_tx|
      next unless eth_tx.is_success?

      # Build deposits directly from this EthTransaction instance
      deposits = eth_tx.build_ethscription_deposits(ethscriptions_block)
      all_deposits.concat(deposits)
    end

    all_deposits
  end
  
  sig { returns(T::Boolean) }
  def is_success?
    status == 1
  end
  
  sig { returns(Hash32) }
  def ethscription_source_hash
    tx_hash
  end

  # Build deposit transactions (EthscriptionTransaction objects) from this L1 transaction
  sig { params(ethscriptions_block: EthscriptionsBlock).returns(T::Array[EthscriptionTransaction]) }
  def build_ethscription_deposits(ethscriptions_block)
    @transactions = []
    
    # 1. Process calldata (try as creation, then as transfer)
    process_calldata

    # 2. Process events (creations and transfers)
    process_events

    @transactions.compact
  end

  private

  def process_calldata
    return unless to_address.present?

    try_calldata_creation
    try_calldata_transfer
  end
  
  def try_calldata_creation
    transaction = EthscriptionTransaction.build_create_ethscription(
      eth_transaction: self,
      creator: normalize_address(from_address),
      initial_owner: normalize_address(to_address),
      content_uri: utf8_input,
      source_type: :input,
      source_index: transaction_index
    )

    @transactions << transaction
  end

  def try_calldata_transfer
    valid_length = if SysConfig.esip5_enabled?(block_number)
      input.bytesize > 0 && input.bytesize % 32 == 0
    else
      input.bytesize == 32
    end
    
    return unless valid_length
    
    input_hex = input.to_hex.delete_prefix('0x')

    ids = input_hex.scan(/.{64}/).map { |hash_hex| normalize_hash("0x#{hash_hex}") }

    # Create transfer transaction
    transaction = EthscriptionTransaction.build_transfer(
      eth_transaction: self,
      from_address: normalize_address(from_address),
      to_address: normalize_address(to_address),
      ethscription_ids: ids,
      source_type: :input,
      source_index: transaction_index
    )

    @transactions << transaction
  end

  def process_events
    ordered_events.each do |log|
      begin
        case log['topics']&.first
        when CreateEthscriptionEventSig
          process_create_event(log)
        when Esip1EventSig
          process_esip1_transfer_event(log)
        when Esip2EventSig
          process_esip2_transfer_event(log)
        end
      rescue Eth::Abi::DecodingError, RangeError => e
        Rails.logger.error "Failed to decode event: #{e.message}"
        next
      end
    end
  end

  def process_create_event(log)
    return unless SysConfig.esip3_enabled?(block_number)
    return unless log['topics'].length == 2

    # Decode event data
    initial_owner = Eth::Abi.decode(['address'], log['topics'].second).first
    content_uri_data = Eth::Abi.decode(['string'], log['data']).first
    content_uri = HexDataProcessor.clean_utf8(content_uri_data)

    transaction = EthscriptionTransaction.build_create_ethscription(
      eth_transaction: self,
      creator: normalize_address(log['address']),
      initial_owner: normalize_address(initial_owner),
      content_uri: content_uri,
      source_type: :event,
      source_index: log['logIndex'].to_i(16)
    )

    @transactions << transaction
  end

  def process_esip1_transfer_event(log)
    return unless SysConfig.esip1_enabled?(block_number)
    return unless log['topics'].length == 3

    # Decode event data
    event_to = Eth::Abi.decode(['address'], log['topics'].second).first
    tx_hash_hex = Eth::Util.bin_to_prefixed_hex(
      Eth::Abi.decode(['bytes32'], log['topics'].third).first
    )

    ethscription_id = normalize_hash(tx_hash_hex)

    transaction = EthscriptionTransaction.build_transfer(
      eth_transaction: self,
      from_address: normalize_address(log['address']),
      to_address: normalize_address(event_to),
      ethscription_ids: ethscription_id,  # Single ID, will be wrapped in array
      source_type: :event,
      source_index: log['logIndex'].to_i(16)
    )

    @transactions << transaction
  end

  def process_esip2_transfer_event(log)
    return unless SysConfig.esip2_enabled?(block_number)
    return unless log['topics'].length == 4

    event_previous_owner = Eth::Abi.decode(['address'], log['topics'].second).first
    event_to = Eth::Abi.decode(['address'], log['topics'].third).first
    tx_hash_hex = Eth::Util.bin_to_prefixed_hex(
      Eth::Abi.decode(['bytes32'], log['topics'].fourth).first
    )

    ethscription_id = normalize_hash(tx_hash_hex)

    transaction = EthscriptionTransaction.build_transfer(
      eth_transaction: self,
      from_address: normalize_address(log['address']),
      to_address: normalize_address(event_to),
      ethscription_ids: ethscription_id,  # Single ID, will be wrapped in array
      enforced_previous_owner: normalize_address(event_previous_owner),
      source_type: :event,
      source_index: log['logIndex'].to_i(16)
    )

    @transactions << transaction
  end

  def ordered_events
    return [] unless logs

    logs.reject { |log| log['removed'] }
        .sort_by { |log| log['logIndex'].to_i(16) }
  end

  def utf8_input
    HexDataProcessor.hex_to_utf8(
      input.to_hex,
      support_gzip: SysConfig.esip7_enabled?(block_number)
    )
  end

  def normalize_address(addr)
    return nil unless addr
    # Handle both Address20 objects and strings
    addr_str = addr.respond_to?(:to_hex) ? addr.to_hex : addr.to_s
    addr_str.downcase
  end

  def normalize_hash(hash)
    return nil unless hash
    # Handle both Hash32 objects and strings
    hash_str = hash.respond_to?(:to_hex) ? hash.to_hex : hash.to_s
    hash_str.downcase
  end
end
