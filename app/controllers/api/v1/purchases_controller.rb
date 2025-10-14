class Api::V1::PurchasesController < ApplicationController
  # Public endpoint for creating purchases
  skip_before_action :authenticate_user!, if: -> { action_name == 'create' }

  # POST /api/v1/purchases
  def create
    user = current_user || User.find_by(email: params[:email])

    if !user
      render json: {
        success: false,
        message: 'No user available for purchase'
      }, status: :unprocessable_entity
      return
    end

    coin_package = CoinPackage.find_by(id: purchase_params[:coin_package_id])

    if !coin_package
      render json: {
        success: false,
        message: 'Invalid coin package'
      }, status: :unprocessable_entity
      return
    end

    # Create purchase using the simplified User model method
    if user.purchase_package(coin_package)
      purchase = user.purchases.last
      render json: {
        success: true,
        message: 'Purchase completed successfully',
        data: {
          purchase: purchase_response(purchase)
        }
      }, status: :created
    else
      render json: {
        success: false,
        message: 'Failed to create purchase'
      }, status: :unprocessable_entity
    end
  end

  private

  def purchase_params
    params.require(:purchase).permit(:coin_package_id, :user_id)
  end

  def purchase_response(purchase)
    {
      id: purchase.id,
      user_id: purchase.user_id,
      coin_package_id: purchase.coin_package_id,
      coins_count: purchase.coins_count,
      price: purchase.price,
      payment_status: purchase.payment_status,
      transaction_id: purchase.transaction_id,
      purchased_at: purchase.purchased_at,
      created_at: purchase.created_at,
      updated_at: purchase.updated_at,
      coin_package: {
        id: purchase.coin_package.id,
        name: purchase.coin_package.name,
        price: purchase.coin_package.price,
        coins_count: purchase.coin_package.coins_count
      }
    }
  end
end
