require 'rails_helper'

RSpec.describe "Transfer Selector End-to-End", type: :integration do
  include EthscriptionsTestHelper

  let(:alice) { valid_address("alice") }
  let(:bob) { valid_address("bob") }
  let(:charlie) { valid_address("charlie") }

  describe "Single vs Multiple Transfer Function Selection" do
    it "uses transferEthscription for single input transfers" do
      # Create an ethscription owned by alice
      id1 = create_test_ethscription(alice)

      # Transfer single ethscription via input
      results = import_l1_block([
        transfer_input(from: alice, to: bob, id: id1)
      ])

      # Get the transaction that was created
      tx = results[:ethscriptions].first
      expect(tx).to be_present

      # Verify it used the singular transfer method
      expect(tx.ethscription_operation).to eq('transfer')
      expect(tx.transfer_ids).to eq([id1])  # Always an array now

      # Check the function selector
      selector = tx.function_selector.unpack1('H*')
      # This should be the selector for transferEthscription(address,bytes32)
      expected_selector = Eth::Util.keccak256('transferEthscription(address,bytes32)')[0...4].unpack1('H*')
      expect(selector).to eq(expected_selector)

      # Verify the calldata encoding
      calldata = tx.input.to_hex.delete_prefix('0x')
      expect(calldata).to start_with(expected_selector)
    end

    it "uses transferEthscriptions for multiple input transfers" do
      # Create ethscriptions owned by alice
      id1 = create_test_ethscription(alice)
      id2 = create_test_ethscription(alice)

      # Transfer multiple ethscriptions via input
      results = import_l1_block([
        transfer_multi_input(from: alice, to: charlie, ids: [id1, id2])
      ])

      # Get the transaction that was created
      tx = results[:ethscriptions].first
      expect(tx).to be_present

      # Verify it used the multiple transfer method
      expect(tx.ethscription_operation).to eq('transfer')
      expect(tx.transfer_ids).to eq([id1, id2])

      # Check the function selector
      selector = tx.function_selector.unpack1('H*')
      # This should be the selector for transferEthscriptions(address,bytes32[])
      expected_selector = Eth::Util.keccak256('transferEthscriptions(address,bytes32[])')[0...4].unpack1('H*')
      expect(selector).to eq(expected_selector)

      # Verify the calldata encoding (address first, then array)
      calldata = tx.input.to_hex.delete_prefix('0x')
      expect(calldata).to start_with(expected_selector)
    end

    it "correctly handles parameter order in transferEthscriptions" do
      # Create ethscriptions
      id1 = create_test_ethscription(alice)
      id2 = create_test_ethscription(alice)
      id3 = create_test_ethscription(alice)

      # Transfer multiple
      results = import_l1_block([
        transfer_multi_input(from: alice, to: bob, ids: [id1, id2, id3])
      ])

      tx = results[:ethscriptions].first

      # Decode the calldata to verify parameter order
      calldata_hex = tx.input.to_hex.delete_prefix('0x')

      # Skip the 4-byte selector
      params_hex = calldata_hex[8..]

      # First 32 bytes should be the address (padded)
      address_param = params_hex[0...64]
      expected_address = bob.downcase.delete_prefix('0x').rjust(64, '0')
      expect(address_param).to include(expected_address[24..]) # Address is right-padded in last 20 bytes
    end

    it "uses correct selector even with ESIP-5 disabled for single transfers" do
      # Test pre-ESIP-5 behavior (single transfers only)
      id1 = create_test_ethscription(alice)

      # Import with ESIP-5 disabled (simulating old block)
      results = import_l1_block(
        [transfer_input(from: alice, to: bob, id: id1)],
        esip_overrides: { esip5: false }
      )

      tx = results[:ethscriptions].first
      expect(tx).to be_present

      # Should still use singular transfer for single ID
      expect(tx.transfer_ids).to eq([id1])  # Always an array now

      # Verify correct function selector
      selector = tx.function_selector.unpack1('H*')
      expected_selector = Eth::Util.keccak256('transferEthscription(address,bytes32)')[0...4].unpack1('H*')
      expect(selector).to eq(expected_selector)
    end
  end

  private

  def create_test_ethscription(owner)
    results = import_l1_block([
      create_input(
        creator: owner,
        to: owner,
        data_uri: "data:,test-#{SecureRandom.hex(4)}"
      )
    ])
    results[:ethscription_ids].first
  end
end