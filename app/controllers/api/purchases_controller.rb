class Api::PurchasesController < ApplicationController
  # before_action :authenticate_user!
  before_action :set_coin_package, only: [:create]

  def create
    # For now, we'll create a pending purchase
    # In a real app, this would integrate with a payment processor
    @purchase = current_user.user_coin_purchases.build(
      coin_package: @coin_package,
      coins_count: @coin_package.coins_count,
      price: @coin_package.price,
      transaction_id: generate_transaction_id,
      payment_status: 'completed' # For demo purposes, mark as completed
    )

    if @purchase.save
      render json: {
        purchase: {
          id: @purchase.id,
          coin_package: {
            id: @coin_package.id,
            name: @coin_package.name,
            coins_count: @coin_package.coins_count
          },
          coins_count: @purchase.coins_count,
          price: @purchase.price,
          payment_status: @purchase.payment_status,
          transaction_id: @purchase.transaction_id,
          purchased_at: @purchase.purchased_at
        },
        new_balance: current_user.reload.available_coins
      }, status: :created
    else
      render json: {
        errors: @purchase.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def set_coin_package
    @coin_package = CoinPackage.active.find(params[:coin_package_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Coin package not found' }, status: :not_found
  end

  def generate_transaction_id
    "TXN_#{Time.current.to_i}_#{SecureRandom.hex(8).upcase}"
  end
end
