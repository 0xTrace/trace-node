require 'rails_helper'

RSpec.describe "EthscriptionTransactionBuilder" do
  describe '.extract_token_params' do
    it 'extracts deploy operation params' do
      content_uri = 'data:,{"p":"erc-20","op":"deploy","tick":"eths","max":"21000000","lim":"1000"}'

      params = Erc20FixedDenominationParser.extract(content_uri)

      expect(params).to eq(['deploy'.b, 'erc-20-fixed-denomination'.b, 'eths'.b, 21000000, 1000, 0])
    end

    it 'extracts mint operation params' do
      content_uri = 'data:,{"p":"erc-20","op":"mint","tick":"eths","id":"1","amt":"1000"}'

      params = Erc20FixedDenominationParser.extract(content_uri)

      expect(params).to eq(['mint'.b, 'erc-20-fixed-denomination'.b, 'eths'.b, 1, 0, 1000])
    end

    it 'returns default params for non-token content' do
      content_uri = 'data:,Hello World!'

      params = Erc20FixedDenominationParser.extract(content_uri)

      expect(params).to eq([''.b, ''.b, ''.b, 0, 0, 0])
    end

    it 'returns default params for invalid JSON' do
      content_uri = 'data:,{invalid json'

      params = Erc20FixedDenominationParser.extract(content_uri)

      expect(params).to eq([''.b, ''.b, ''.b, 0, 0, 0])
    end

    it 'handles unknown operations with protocol/tick' do
      content_uri = 'data:,{"p":"new-proto","op":"custom","tick":"test"}'

      params = Erc20FixedDenominationParser.extract(content_uri)

      expect(params).to eq([''.b, ''.b, ''.b, 0, 0, 0])
    end
  end
end
