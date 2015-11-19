require 'spec_helper'

describe CoinbaseController do

  describe 'success' do
    let!(:person) { create(:person) }
    let(:cart) { person.shopping_cart }
    let(:www_receipt_url) { 'http://fake.notcom/receipts/1' }

    describe 'order created' do
      let!(:order) { create(:transaction_order) }

      before do
        # Update shopping cart with the order ID,
        # which happens after an order is successfully completed.
        cart.update_attribute(:order, order)

        Transaction::Order.any_instance.stub(:www_receipt_url).and_return(www_receipt_url)
      end

      it 'should redirect to frontend receipt page' do
        get :success, shopping_cart_id: cart.id
        response.should redirect_to www_receipt_url
      end
    end

    describe 'order not created' do
      it 'should redirect to frontend orders index page' do
        get :success, shopping_cart_id: cart.id
        response.should redirect_to Api::Application.config.www_receipts_url
      end
    end
  end

end
